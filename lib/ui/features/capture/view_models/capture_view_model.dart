import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../data/services/scanner/live_preview_source.dart';
import '../../../../domain/models/capture_models.dart';
import '../../../../domain/models/project.dart';
import '../../../../domain/models/provider_info.dart';
import '../../../../domain/models/scan_page.dart';
import '../../../../domain/providers/capture_provider.dart';
import '../../../../domain/repositories/page_repository.dart';
import '../../../../domain/repositories/project_repository.dart';
import '../../../../domain/repositories/settings_repository.dart';
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
    required SettingsRepository settingsRepository,
    this.replacePageId,
    this.preferredCaptureMode,
    this.resultPreviewHold = const Duration(milliseconds: 900),
    this.onNeedsCropCorrection,
  }) : _captureProvider = captureProvider,
       _capturePageUseCase = capturePageUseCase,
       _processBookSpreadUseCase = processBookSpreadUseCase,
       _projectRepository = projectRepository,
       _pageRepository = pageRepository,
       _settingsRepository = settingsRepository;

  final String projectId;

  /// When set, this session replaces exactly this page's image content
  /// in place (the "Rescan" action, SPEC 6.3) instead of appending new
  /// pages — see [captureManually] and [replacementComplete].
  final String? replacePageId;

  /// Home quick-action override (e.g. [CaptureMode.idCard]).
  final CaptureMode? preferredCaptureMode;

  /// How long to hold the processed (cropped/perspective-corrected) page
  /// on screen after enhance finishes, so the user sees the final look
  /// before the live camera returns for the next shot. Tests pass
  /// [Duration.zero] to skip the pause.
  /// Kept so existing tests can pass a hold. Shots no longer wait on it.
  // ignore: unused_field
  final Duration resultPreviewHold;

  /// Called when a still was saved but no confident page quad was found.
  /// Kept for tests/DI; the capture session no longer navigates mid-scan —
  /// corner correction happens in the post-capture edit flow instead.
  final void Function(String pageId)? onNeedsCropCorrection;
  final CaptureProvider _captureProvider;
  final CapturePageUseCase _capturePageUseCase;
  final ProcessBookSpreadUseCase _processBookSpreadUseCase;
  final ProjectRepository _projectRepository;
  final PageRepository _pageRepository;
  final SettingsRepository _settingsRepository;

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

  /// First page in sequence order — used by Continue → crop-first flow.
  Future<String?> firstPageIdOrdered() async {
    final project = await _projectRepository.getProject(projectId);
    final all = await _pageRepository.getPages(projectId);
    if (all.isEmpty) return null;
    final byId = {for (final p in all) p.id: p};
    if (project != null && project.pageOrder.isNotEmpty) {
      for (final id in project.pageOrder) {
        if (byId.containsKey(id)) return id;
      }
    }
    all.sort((a, b) => a.sequence.compareTo(b.sequence));
    return all.first.id;
  }

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

  int? get previewTextureId => _captureProvider.previewTextureId;

  double get previewAspectRatio => _captureProvider.previewAspectRatio;

  /// Plugin-owned preview widget when the adapter supplies one; otherwise
  /// the screen falls back to [previewTextureId].
  Widget? get livePreview {
    final provider = _captureProvider;
    if (provider is LivePreviewSource) {
      return (provider as LivePreviewSource).buildLivePreview();
    }
    return null;
  }

  FlashMode _flashMode = FlashMode.off;
  FlashMode get flashMode => _flashMode;

  double _zoomLevel = 0;
  double get zoomLevel => _zoomLevel;

  Offset? _focusIndicator;
  Offset? get focusIndicator => _focusIndicator;

  String? _shutterHint;
  String? get shutterHint => _shutterHint;

  bool _autoCaptureEnabled = false;
  bool get autoCaptureEnabled => _autoCaptureEnabled;

  bool _captureFromAuto = false;
  bool get captureFromAuto => _captureFromAuto;

  bool _awaitingSceneChange = false;
  int? _stableSinceMs;

  /// Visible Auto dwell so the shutter can show a TapScanner-style timer.
  /// Short enough for SPEC 9.2, long enough to read 2→1 on the ring.
  static const _autoCaptureStableMs = 2000;

  CaptureSettings _captureSettings = const CaptureSettings();

  bool _counting = false;

  int _countdownRemaining = 0;

  /// Seconds remaining in an active pre-capture countdown
  /// ([CaptureSettings.countdownSeconds]), or 0 when none is running.
  int get countdownRemaining => _countdownRemaining;

  /// 0–1 progress through the Auto stable window while gates stay ready.
  double get autoCaptureProgress {
    if (!_autoCaptureEnabled ||
        _awaitingSceneChange ||
        _capturing ||
        replacePageId != null) {
      return 0;
    }
    final since = _stableSinceMs;
    final analysis = _latestAnalysis;
    if (since == null || analysis == null) return 0;
    if (!(analysis.gatesSatisfied && analysis.quad != null)) return 0;
    final elapsed = analysis.timestampMs - since;
    return (elapsed / _autoCaptureStableMs).clamp(0.0, 1.0);
  }

  /// Whole seconds left before Auto fires, or null when not counting.
  int? get autoCaptureSecondsRemaining {
    final progress = autoCaptureProgress;
    if (progress <= 0 || progress >= 1) return null;
    final since = _stableSinceMs!;
    final elapsed = _latestAnalysis!.timestampMs - since;
    final remainingMs = _autoCaptureStableMs - elapsed;
    return ((remainingMs + 999) ~/ 1000).clamp(1, 99);
  }

  /// Thumbnail/processed path of the most recently persisted page this session.
  String? _lastPagePreviewPath;
  String? get lastPagePreviewPath => _lastPagePreviewPath;

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
    final pages = await _pageRepository.getPages(projectId);
    _pageCount = pages.length;
    _captureSettings = (await _settingsRepository.getSettings()).captureSettings;
    _autoCaptureEnabled = _captureSettings.autoCaptureEnabled;

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
          : (preferredCaptureMode ?? CaptureMode.singlePage);
      await _captureProvider.openSession(mode);
      _capabilities = await _captureProvider.capabilities();
      _sessionOpen = true;
      _analysisSubscription = _captureProvider.analysisStream().listen(
        _onAnalysis,
      );
      _notify();
    } on ProviderException catch (e) {
      _error = e;
      _notify();
    } catch (e) {
      _error = ProviderException(ProviderErrorCategory.unknown, e.toString());
      _notify();
    }
  }

  /// Auto-capture when the live quad stays stable (SPEC 5.1/5.2, 17.3).
  /// Manual mode is a session toggle so the user can line up a shot without
  /// the shutter firing. Duplicate avoidance: after a capture, wait for the
  /// scene to become unstable before arming again.
  void _onAnalysis(FrameAnalysis analysis) {
    _latestAnalysis = analysis;
    if (!analysis.focusAcceptable) {
      _shutterHint = 'focusing';
    } else if (!analysis.motionBelowThreshold) {
      _shutterHint = 'holdStill';
    } else {
      _shutterHint = null;
    }

    if (_autoCaptureEnabled &&
        replacePageId == null &&
        !_capturing &&
        _sessionOpen) {
      _maybeAutoCapture(analysis);
    }
    _notify();
  }

  void _maybeAutoCapture(FrameAnalysis analysis) {
    final ready = analysis.gatesSatisfied && analysis.quad != null;
    if (_awaitingSceneChange) {
      if (!ready) _awaitingSceneChange = false;
      return;
    }
    if (!ready) {
      _stableSinceMs = null;
      return;
    }
    _stableSinceMs ??= analysis.timestampMs;
    if (analysis.timestampMs - _stableSinceMs! < _autoCaptureStableMs) {
      return;
    }
    // Continuous capture skips the "wait for an unstable frame" dedup gate
    // so the next stable window can fire again immediately instead of
    // requiring the scene to change first (SPEC 6.1's "automatic continuous
    // capture").
    _awaitingSceneChange = !_captureSettings.continuousCapture;
    _stableSinceMs = null;
    unawaited(captureManually(fromAuto: true));
  }

  /// Ticks [_countdownRemaining] down to 0 once per second
  /// (SPEC 6.1's "configurable countdown"), notifying listeners each tick so
  /// the screen can render it. Returns false if the session closed or this
  /// view model was disposed mid-countdown, in which case the capture must
  /// not proceed.
  Future<bool> _runCountdown() async {
    _counting = true;
    _countdownRemaining = _captureSettings.countdownSeconds;
    _notify();
    while (_countdownRemaining > 0) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (_disposed || !_sessionOpen) {
        _counting = false;
        _countdownRemaining = 0;
        return false;
      }
      _countdownRemaining--;
      _notify();
    }
    _counting = false;
    _notify();
    return true;
  }

  void setAutoCaptureEnabled(bool enabled) {
    _autoCaptureEnabled = enabled;
    _awaitingSceneChange = false;
    _stableSinceMs = null;
    _notify();
  }

  void toggleAutoCapture() => setAutoCaptureEnabled(!_autoCaptureEnabled);

  /// Returns the page produced by this capture.
  ///
  /// A document photo is cropped and filtered. A book photo is one full
  /// page, stored as shot, so the next page can be taken immediately.
  /// Apps such as Adobe Scan and vFlat work this way: facing-page splits
  /// are a separate step, never a silent cut down the middle.
  ///
  /// Live quality warnings stay on the banner and are stored on the page;
  /// they do not swallow a shutter tap. SPEC 9.2 requires manual capture on
  /// every device — on the Galaxy A05 the live analyzer almost always
  /// reports blur/clipped-edges, so a gate here produced empty Review
  /// sessions after the user tapped shutter then Done.
  Future<List<ScanPage>> captureManually({bool fromAuto = false}) async {
    if (_capturing || !_sessionOpen || _counting) return const [];
    if (_captureSettings.countdownSeconds > 0) {
      final proceed = await _runCountdown();
      if (!proceed) return const [];
    }
    _capturing = true;
    _captureFromAuto = fromAuto;
    _notify();
    try {
      final stills = await _captureStills();
      if (stills.isEmpty) return const [];
      if (_captureSettings.hapticConfirmation) HapticFeedback.mediumImpact();
      if (_captureSettings.audioConfirmation) {
        SystemSound.play(SystemSoundType.click);
      }
      final still = stills.first;
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
      final pages = <ScanPage>[];
      for (final item in stills) {
        pages.addAll(
          await _persistCapturedStill(
            item,
            sequence: _pageCount + pages.length,
          ),
        );
      }
      _pageCount += pages.length;
      final first = pages.first;
      _lastPagePreviewPath = first.originalImagePath;
      // Processing (crop, document filter) waits until the user asks for it
      // on Review. The camera returns as soon as the photo is saved.
      return pages;
    } on ProviderException catch (e) {
      if (e.category == ProviderErrorCategory.cancelled) return const [];
      _error = e;
      return const [];
    } catch (e) {
      _error = ProviderException(ProviderErrorCategory.unknown, e.toString());
      return const [];
    } finally {
      _capturing = false;
      _captureFromAuto = false;
      _frozenPreviewPath = null;
      _resultPreviewPath = null;
      _notify();
    }
  }

  Future<List<StillCapture>> _captureStills() async {
    final provider = _captureProvider;
    if (replacePageId == null && provider is BatchDocumentCapture) {
      final batch = provider as BatchDocumentCapture;
      return batch.scanDocuments(maxPages: 20);
    }
    return [await provider.captureStill()];
  }

  Future<List<ScanPage>> importStill(String imagePath) {
    return _persistImported(
      StillCapture(
        originalImagePath: imagePath,
        detectedQuad: null,
        qualityScore: 0.8,
        warnings: const {},
        capturedAtMs: DateTime.now().millisecondsSinceEpoch,
        providerInfo: const ProviderInfo(
          providerName: 'gallery-import',
          adapterVersion: '1.0.0',
        ),
      ),
    );
  }

  Future<List<ScanPage>> _persistImported(StillCapture still) async {
    if (_capturing || !_sessionOpen) return const [];
    _capturing = true;
    _notify();
    try {
      final pages = await _persistCapturedStill(still, sequence: _pageCount);
      _pageCount += pages.length;
      return pages;
    } finally {
      _capturing = false;
      _notify();
    }
  }

  Future<List<ScanPage>> _persistCapturedStill(
    StillCapture still, {
    required int sequence,
  }) {
    if (_projectType == ProjectType.book) {
      return _processBookSpreadUseCase.processSinglePage(
        capture: still,
        projectId: projectId,
        sequence: sequence,
      );
    }
    return _capturePageUseCase
        .saveShot(
          capture: still,
          projectId: projectId,
          sequence: sequence,
        )
        .then((page) => [page]);
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
