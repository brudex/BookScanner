import 'dart:async';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../domain/models/capture_models.dart';
import '../../../../domain/models/geometry.dart';
import '../../../../domain/models/project.dart';
import '../../../../domain/models/provider_info.dart';
import '../../../../domain/models/scan_page.dart';
import '../../../../domain/providers/capture_provider.dart';
import '../../../../domain/repositories/page_repository.dart';
import '../../../../domain/repositories/project_repository.dart';
import '../../../../domain/use_cases/capture_page_use_case.dart';
import '../../../../domain/use_cases/process_book_spread_use_case.dart';

enum CapturePermissionState { unknown, granted, denied, permanentlyDenied }

class CaptureViewModel extends ChangeNotifier {
  CaptureViewModel({
    required this.projectId,
    required CaptureProvider captureProvider,
    required CapturePageUseCase capturePageUseCase,
    required ProcessBookSpreadUseCase processBookSpreadUseCase,
    required ProjectRepository projectRepository,
    required PageRepository pageRepository,
    this.replacePageId,
    this.resultPreviewHold = const Duration(milliseconds: 900),
    this.onNeedsCropCorrection,
  }) : _captureProvider = captureProvider,
       _capturePageUseCase = capturePageUseCase,
       _processBookSpreadUseCase = processBookSpreadUseCase,
       _projectRepository = projectRepository,
       _pageRepository = pageRepository;

  final String projectId;

  /// When set, this session replaces exactly this page's image content
  /// in place (the "Rescan" action, SPEC 6.3) instead of appending new
  /// pages — see [captureManually] and [replacementComplete].
  final String? replacePageId;

  /// How long to hold the processed (cropped/perspective-corrected) page
  /// on screen after enhance finishes, so the user sees the final look
  /// before the live camera returns for the next shot. Tests pass
  /// [Duration.zero] to skip the pause.
  final Duration resultPreviewHold;

  /// Called when a still was saved but no confident page quad was found,
  /// so the user should adjust corners instead of accepting a fake crop.
  final void Function(String pageId)? onNeedsCropCorrection;
  final CaptureProvider _captureProvider;
  final CapturePageUseCase _capturePageUseCase;
  final ProcessBookSpreadUseCase _processBookSpreadUseCase;
  final ProjectRepository _projectRepository;
  final PageRepository _pageRepository;

  CapturePermissionState _permissionState = CapturePermissionState.unknown;
  CapturePermissionState get permissionState => _permissionState;

  bool _sessionOpen = false;
  bool get sessionOpen => _sessionOpen;

  ScannerCapabilities? _capabilities;
  ScannerCapabilities? get capabilities => _capabilities;

  FrameAnalysis? _latestAnalysis;
  FrameAnalysis? get latestAnalysis => _latestAnalysis;

  StreamSubscription<FrameAnalysis>? _analysisSubscription;

  int _pageCount = 0;
  int get pageCount => _pageCount;

  bool _capturing = false;
  bool get capturing => _capturing;

  /// Path of the just-captured still, set once `captureStill()` returns and
  /// cleared once enhancement finishes -- lets the screen freeze on the
  /// actual captured frame (with a loading indicator over it) instead of
  /// continuing to show the live feed while detect/enhance runs. The
  /// shutter overlay (`capturing && frozenPreviewPath == null`) covers the
  /// gap between tap and this path becoming available.
  String? _frozenPreviewPath;
  String? get frozenPreviewPath => _frozenPreviewPath;

  /// Path of the processed page shown after enhance, before returning to
  /// the live camera -- the cropped, perspective-corrected document with
  /// the background already removed (TapScanner-style "final look").
  String? _resultPreviewPath;
  String? get resultPreviewPath => _resultPreviewPath;

  Object? _error;
  Object? get error => _error;

  /// True once a single replacement capture has succeeded in a
  /// [replacePageId] session -- the screen should navigate back to Review
  /// as soon as this flips true, since a rescan is a single-shot action,
  /// not an open-ended multi-page session.
  bool _replacementComplete = false;
  bool get replacementComplete => _replacementComplete;

  ProjectType? _projectType;
  ProjectType? get projectType => _projectType;

  PageOrderDirection _pageOrderDirection = PageOrderDirection.leftToRight;

  int? get previewTextureId => _captureProvider.previewTextureId;

  double get previewAspectRatio => _captureProvider.previewAspectRatio;

  FlashMode _flashMode = FlashMode.off;
  FlashMode get flashMode => _flashMode;

  double _zoomLevel = 0;
  double get zoomLevel => _zoomLevel;

  Offset? _focusIndicator;
  Offset? get focusIndicator => _focusIndicator;

  bool _awaitingQualityOverride = false;
  bool get awaitingQualityOverride => _awaitingQualityOverride;

  String? _shutterHint;
  String? get shutterHint => _shutterHint;

  bool _disposed = false;

  /// Every `notifyListeners()` call in this class runs at the end of an
  /// awaited async gap (a permission request, `_openSession`, a capture
  /// pipeline run) or from a stream callback, any of which can complete
  /// *after* the screen has navigated away and disposed this view model --
  /// observed on-device as an uncaught "A CaptureViewModel was used after
  /// being disposed" crash from a capture that was still processing when
  /// the user backed out of the Capture screen. `dispose()` cancels the
  /// analysis subscription but does not (and cannot cleanly) cancel an
  /// in-flight `captureManually()` call, so the guard belongs here instead.
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    final project = await _projectRepository.getProject(projectId);
    _projectType = project?.type;
    _pageOrderDirection =
        project?.metadata.pageOrderDirection ?? PageOrderDirection.leftToRight;
    final pages = await _pageRepository.getPages(projectId);
    _pageCount = pages.length;

    final status = await Permission.camera.status;
    _permissionState = _mapStatus(status);
    _notify();

    if (_permissionState == CapturePermissionState.granted) {
      await _openSession();
    }
  }

  Future<void> requestPermission() async {
    final status = await Permission.camera.request();
    _permissionState = _mapStatus(status);
    _notify();
    if (_permissionState == CapturePermissionState.granted) {
      await _openSession();
    }
  }

  CapturePermissionState _mapStatus(PermissionStatus status) {
    if (status.isGranted) return CapturePermissionState.granted;
    if (status.isPermanentlyDenied) {
      return CapturePermissionState.permanentlyDenied;
    }
    return CapturePermissionState.denied;
  }

  Future<void> _openSession() async {
    try {
      final mode = _projectType == ProjectType.book
          ? CaptureMode.bookSpread
          : CaptureMode.singlePage;
      _capabilities = await _captureProvider.capabilities();
      await _captureProvider.openSession(mode);
      _sessionOpen = true;
      _analysisSubscription = _captureProvider.analysisStream().listen(
        _onAnalysis,
      );
      _notify();
    } on ProviderException catch (e) {
      _error = e;
      _notify();
    }
  }

  /// Deliberate SPEC 17.3 deviation: this used to auto-fire a capture once
  /// a frame held all quality gates for a stable window. Tried on-device
  /// and rejected -- the shutter button showed the same "capturing" spinner
  /// an auto-fired capture used as a manual one, so it visibly locked out
  /// and spun on its own while the user was still lining up the shot,
  /// reading as broken rather than helpful. Capture is manual-only now;
  /// this still records the latest frame for the warning banner and the
  /// capture frame guide's color.
  void _onAnalysis(FrameAnalysis analysis) {
    _latestAnalysis = analysis;
    if (!analysis.focusAcceptable) {
      _shutterHint = 'focusing';
    } else if (!analysis.motionBelowThreshold) {
      _shutterHint = 'holdStill';
    } else {
      _shutterHint = null;
    }
    _notify();
  }

  bool _hasBlockingWarnings(FrameAnalysis? analysis) {
    if (analysis == null) return false;
    final warnings = analysis.warnings.where((w) => w != QualityWarning.none);
    return warnings.isNotEmpty ||
        !analysis.focusAcceptable ||
        !analysis.motionBelowThreshold ||
        !analysis.exposureAcceptable;
  }

  /// Returns the page(s) produced by this capture: one for a normal
  /// document page, or two (already split, ordered per the project's
  /// [PageOrderDirection]) for a book spread (SPEC 5.2).
  Future<List<ScanPage>> captureManually({
    bool bypassQualityGate = false,
  }) async {
    if (_capturing || !_sessionOpen) return const [];
    if (!bypassQualityGate && _hasBlockingWarnings(_latestAnalysis)) {
      _awaitingQualityOverride = true;
      _notify();
      return const [];
    }
    _awaitingQualityOverride = false;
    _capturing = true;
    _notify();
    try {
      final still = await _captureProvider.captureStill();
      _frozenPreviewPath = still.originalImagePath;
      _notify();
      final replaceId = replacePageId;
      if (replaceId != null) {
        // Always the single-page replace path, even in a book project --
        // rescanning one half of a split spread replaces just that page's
        // image, not the whole spread pipeline.
        final replaced = await _capturePageUseCase.replacePage(
          replaceId,
          still,
        );
        _replacementComplete = true;
        return [replaced];
      }
      final pages = _projectType == ProjectType.book
          ? await _processBookSpreadUseCase.processCapture(
              capture: still,
              projectId: projectId,
              sequence: _pageCount,
              pageOrderDirection: _pageOrderDirection,
            )
          : [
              await _capturePageUseCase.processCapture(
                capture: still,
                projectId: projectId,
                sequence: _pageCount,
              ),
            ];
      _pageCount += pages.length;
      final first = pages.first;
      final uncertainCrop =
          (first.cropPoints == null || first.cropPoints == Quad.fullFrame) &&
          still.detectionConfidence < DetectionThresholds.minConfidence &&
          still.detectedQuad == null;
      if (uncertainCrop) {
        onNeedsCropCorrection?.call(first.id);
      }
      final resultPath = first.processedImagePath ?? first.thumbnailPath;
      _frozenPreviewPath = null;
      if (replaceId == null &&
          resultPath != null &&
          resultPreviewHold > Duration.zero) {
        _resultPreviewPath = resultPath;
        _notify();
        await Future<void>.delayed(resultPreviewHold);
      }
      return pages;
    } on ProviderException catch (e) {
      _error = e;
      return const [];
    } finally {
      _capturing = false;
      _frozenPreviewPath = null;
      _resultPreviewPath = null;
      _notify();
    }
  }

  /// Applies the name the user chose in the post-capture "Name this scan"
  /// dialog, replacing the generic mode-based default title
  /// ([NewScanSheetRoute] seeds it as just "Document"/"Book").
  Future<void> renameProject(String title) =>
      _projectRepository.renameProject(projectId, title);

  Future<void> setFlashMode(FlashMode mode) async {
    _flashMode = mode;
    await _captureProvider.setFlashMode(mode);
    _notify();
  }

  Future<void> cycleFlashMode() async {
    final next = switch (_flashMode) {
      FlashMode.off => FlashMode.on,
      FlashMode.on => FlashMode.auto,
      FlashMode.auto => FlashMode.torch,
      FlashMode.torch => FlashMode.off,
    };
    await setFlashMode(next);
  }

  Future<void> setZoom(double level) async {
    _zoomLevel = level.clamp(0.0, 1.0);
    await _captureProvider.setZoom(_zoomLevel);
    _notify();
  }

  Future<void> setFocusAndExposurePoint(double x, double y) async {
    _focusIndicator = Offset(x, y);
    await _captureProvider.setFocusAndExposurePoint(x, y);
    _notify();
  }

  Future<void> closeSession() async {
    await _analysisSubscription?.cancel();
    if (_sessionOpen) {
      await _captureProvider.closeSession();
      _sessionOpen = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(closeSession());
    super.dispose();
  }
}
