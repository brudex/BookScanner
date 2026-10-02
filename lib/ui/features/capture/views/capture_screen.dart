import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../domain/models/capture_models.dart';
import '../../../../domain/models/geometry.dart';
import '../../../../domain/models/project.dart';
import '../../../../domain/providers/capture_provider.dart';
import '../../../../domain/repositories/page_repository.dart';
import '../../../../domain/repositories/project_repository.dart';
import '../../../../domain/repositories/settings_repository.dart';
import '../../../../domain/use_cases/capture_page_use_case.dart';
import '../../../../domain/use_cases/process_book_spread_use_case.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../../routing/app_router.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/discard_unsaved_capture.dart';
import '../../../core/theme/app_theme.dart';
import '../view_models/capture_view_model.dart';
import '../preview_layout.dart';
import 'camera_preview_view.dart';
import '../../page_review/views/crop_correction_screen.dart';

/// Normalized fractional insets of the fixed capture frame guide from each
/// edge of the preview -- shared with [Quad.captureGuide] so detection's
/// framed-page fallback cannot drift from what the painter draws.
const _guideHorizontalInset = Quad.guideHorizontalInset;
const _guideVerticalInset = Quad.guideVerticalInset;

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({
    super.key,
    required this.projectId,
    this.replacePageId,
    this.captureMode,
    this.viewModel,
  });

  final String projectId;

  /// When set, this session replaces exactly this page's image (the
  /// "Rescan" action from Page Review) instead of appending new pages.
  final String? replacePageId;

  /// Optional capture mode override (e.g. [CaptureMode.idCard] from Home).
  final CaptureMode? captureMode;
  final CaptureViewModel? viewModel;

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  late final CaptureViewModel _viewModel;
  bool _showGrid = false;
  bool _leavingForReview = false;

  @override
  void initState() {
    super.initState();
    _viewModel =
        widget.viewModel ??
        CaptureViewModel(
          projectId: widget.projectId,
          captureProvider: locator<CaptureProvider>(),
          capturePageUseCase: locator<CapturePageUseCase>(),
          processBookSpreadUseCase: locator<ProcessBookSpreadUseCase>(),
          projectRepository: locator<ProjectRepository>(),
          pageRepository: locator<PageRepository>(),
          settingsRepository: locator<SettingsRepository>(),
          replacePageId: widget.replacePageId,
          preferredCaptureMode: widget.captureMode,
        );
    _viewModel.initialize();
    _viewModel.addListener(_onViewModelChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final l10n = AppLocalizations.of(context);
    _viewModel.idFrontLabel = l10n.scanIdSideFront;
    _viewModel.idBackLabel = l10n.scanIdSideBack;
  }

  void _onViewModelChanged() {
    if (_viewModel.replacementComplete && mounted) {
      context.pop();
    }
    if (_viewModel.idScanFinished && !_leavingForReview && mounted) {
      _leavingForReview = true;
      unawaited(_openIdReview());
    }
  }

  Future<void> _openIdReview() async {
    await _viewModel.closeSession();
    if (!mounted) return;
    context.pushReplacement(AppRoutes.pageReviewFor(widget.projectId));
  }

  @override
  void dispose() {
    _viewModel.removeListener(_onViewModelChanged);
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: ListenableBuilder(
        listenable: _viewModel,
        builder: (context, _) => _buildBody(context, l10n),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n) {
    switch (_viewModel.permissionState) {
      case CapturePermissionState.unknown:
        return const Center(child: CircularProgressIndicator());
      case CapturePermissionState.denied:
        return _PermissionRationale(
          message: l10n.capturePermissionRationale,
          actionLabel: l10n.captureTitle,
          onAction: _viewModel.requestPermission,
        );
      case CapturePermissionState.permanentlyDenied:
        return _PermissionRationale(
          message: l10n.capturePermissionDenied,
          actionLabel: l10n.openSettings,
          onAction: openAppSettings,
        );
      case CapturePermissionState.granted:
        return _buildCaptureUi(context, l10n);
    }
  }

  Widget _buildCaptureUi(BuildContext context, AppLocalizations l10n) {
    if (_viewModel.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '${_viewModel.error}',
            style: const TextStyle(color: Colors.white),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (!_viewModel.sessionOpen) {
      // Permission is granted, but `_openSession()` hasn't resolved yet.
      // Without this gate the shutter button below would render tappable
      // immediately (nothing here depends on `sessionOpen`), and a tap
      // before the session actually opens is silently swallowed by
      // `captureManually`'s `!_sessionOpen` guard -- no error, no capture,
      // just a lost tap the user has no way to notice.
      return const Center(
        child: CircularProgressIndicator(
          key: ValueKey('captureSessionOpening'),
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_viewModel.resultPreviewPath != null)
          _ProcessedResultPreview(path: _viewModel.resultPreviewPath!)
        else if (_viewModel.frozenPreviewPath != null)
          _FrozenCapturePreview(
            path: _viewModel.frozenPreviewPath!,
            zoomIntoGuide: _viewModel.projectType != ProjectType.book,
          )
        else
          _LivePreview(
            textureId: _viewModel.previewTextureId,
            preview: _viewModel.livePreview,
            aspectRatio: _viewModel.previewAspectRatio,
            analysis: _viewModel.latestAnalysis,
            focusIndicator: _viewModel.focusIndicator,
            showGrid: _showGrid,
            onTapFocus: _viewModel.setFocusAndExposurePoint,
          ),
        if (_viewModel.capturing &&
            _viewModel.frozenPreviewPath == null &&
            _viewModel.resultPreviewPath == null)
          _viewModel.captureFromAuto
              ? const _AutoCaptureFlash()
              : const _CaptureShutterScrim(),
        SafeArea(
          child: Column(
            children: [
              _CaptureTopBar(
                l10n: l10n,
                flashMode: _viewModel.flashMode,
                autoCaptureEnabled: _viewModel.autoCaptureEnabled,
                capturing: _viewModel.capturing,
                showGrid: _showGrid,
                onBack: () async {
                  if (_viewModel.pageCount > 0) {
                    await _viewModel.closeSession();
                    if (!mounted) return;
                    await discardUnsavedCapture(widget.projectId);
                    if (!mounted) return;
                    this.context.go(AppRoutes.library);
                    return;
                  }
                  if (!mounted) return;
                  this.context.pop();
                },
                onToggleGrid: () => setState(() => _showGrid = !_showGrid),
                onFlash: _viewModel.cycleFlashMode,
                onToggleAuto: _viewModel.toggleAutoCapture,
              ),
              _WarningBanner(
                analysis: _viewModel.latestAnalysis,
                l10n: l10n,
                shutterHint: _viewModel.shutterHint,
              ),
              const Spacer(),
              _CaptureControls(
                pageCount: _viewModel.pageCount,
                capturing: _viewModel.capturing,
                lastPagePreviewPath: _viewModel.lastPagePreviewPath,
                isBook: _viewModel.projectType == ProjectType.book,
                isIdScan: _viewModel.isIdScan,
                l10n: l10n,
                onShutter: () => _viewModel.captureManually(),
                onImport: _importFromGallery,
                onDone: () async {
                  if (_viewModel.pageCount == 0) return;
                  await _viewModel.closeSession();
                  if (!mounted) return;
                  // Books skip the post-capture crop/filter walk and open
                  // the existing Review pages screen. Documents still crop
                  // then filter page by page.
                  if (_viewModel.projectType == ProjectType.book) {
                    this.context.pushReplacement(
                      AppRoutes.pageReviewFor(widget.projectId),
                    );
                    return;
                  }
                  final pageId = await _viewModel.firstPageIdOrdered();
                  if (!mounted || pageId == null) return;
                  this.context.pushReplacement(
                    AppRoutes.cropCorrectionFor(widget.projectId, pageId),
                    extra: CropFlowMode.postCapture,
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _importFromGallery() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null || !mounted) return;
    await _viewModel.importStill(file.path);
  }
}

/// Dim + spinner over the live preview from the shutter tap until the
/// JPEG is on disk and [_FrozenCapturePreview] can take over. The native
/// texture cannot be snapshotted, so this is the freeze-on-click cue.
class _CaptureShutterScrim extends StatelessWidget {
  const _CaptureShutterScrim();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      key: ValueKey('captureShutterScrim'),
      fit: StackFit.expand,
      children: [
        ColoredBox(color: Colors.black38),
        Center(
          child: CircularProgressIndicator(
            key: ValueKey('captureProcessingIndicator'),
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

class _AutoCaptureFlash extends StatelessWidget {
  const _AutoCaptureFlash();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      key: ValueKey('captureAutoFlash'),
      color: Color(0x66FFFFFF),
    );
  }
}

class _CaptureTopBar extends StatelessWidget {
  const _CaptureTopBar({
    required this.l10n,
    required this.flashMode,
    required this.autoCaptureEnabled,
    required this.capturing,
    required this.showGrid,
    required this.onBack,
    required this.onToggleGrid,
    required this.onFlash,
    required this.onToggleAuto,
  });

  final AppLocalizations l10n;
  final FlashMode flashMode;
  final bool autoCaptureEnabled;
  final bool capturing;
  final bool showGrid;
  final VoidCallback onBack;
  final VoidCallback onToggleGrid;
  final VoidCallback onFlash;
  final VoidCallback onToggleAuto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(
              LucideIcons.chevronLeft,
              color: Colors.white,
              size: 28,
            ),
          ),
          IconButton(
            key: const ValueKey('captureGridButton'),
            tooltip: l10n.captureGrid,
            onPressed: onToggleGrid,
            icon: Icon(
              showGrid ? LucideIcons.grid2x2 : LucideIcons.grid2x2X,
              color: Colors.white,
            ),
          ),
          IconButton(
            key: const ValueKey('captureFlashButton'),
            onPressed: capturing ? null : onFlash,
            tooltip: switch (flashMode) {
              FlashMode.off => l10n.captureFlashOff,
              FlashMode.on => l10n.captureFlashOn,
              FlashMode.auto => l10n.captureFlashAuto,
              FlashMode.torch => l10n.captureTorch,
            },
            icon: Icon(switch (flashMode) {
              FlashMode.off => LucideIcons.zapOff,
              FlashMode.on => LucideIcons.zap,
              FlashMode.auto => LucideIcons.sparkles,
              FlashMode.torch => LucideIcons.flashlight,
            }, color: Colors.white),
          ),
          const Spacer(),
          TextButton(
            key: const ValueKey('captureAutoToggle'),
            onPressed: capturing ? null : onToggleAuto,
            child: Semantics(
              button: true,
              label: autoCaptureEnabled
                  ? l10n.captureAutoLabel
                  : l10n.captureManualLabel,
              child: Row(
                children: [
                  Text(
                    autoCaptureEnabled
                        ? l10n.captureAutoLabel
                        : l10n.captureManualLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(LucideIcons.arrowLeftRight, color: Colors.white),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown from the moment a still is captured until it's fully processed and
/// added as a page: the actual captured frame (not the continuing live
/// feed), animating a zoom into just the region inside the capture frame
/// guide -- the same TapScanner-style cue used elsewhere in this screen,
/// here showing the user up front that content outside the guide is
/// discarded, not just implying it -- with a loading indicator over it so
/// it's visually obvious a specific shot is being turned into a page rather
/// than the app just looking stuck.
///
/// `fit: BoxFit.contain` matches the live preview's letterboxed mapping.
class _FrozenCapturePreview extends StatelessWidget {
  const _FrozenCapturePreview({required this.path, this.zoomIntoGuide = true});

  final String path;

  /// Document scans zoom into the frame guide. Book scans keep the full
  /// photo on screen — nothing outside the guide is thrown away.
  final bool zoomIntoGuide;

  static const _guideContentWidthFraction = 1 - 2 * _guideHorizontalInset;
  static const _guideContentHeightFraction = 1 - 2 * _guideVerticalInset;

  @override
  Widget build(BuildContext context) {
    return Stack(
      key: const ValueKey('captureFrozenPreview'),
      fit: StackFit.expand,
      children: [
        ClipRect(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: zoomIntoGuide ? 1 : 0),
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            builder: (context, t, child) => Transform(
              alignment: Alignment.center,
              transform: Matrix4.diagonal3Values(
                1 + (1 / _guideContentWidthFraction - 1) * t,
                1 + (1 / _guideContentHeightFraction - 1) * t,
                1,
              ),
              child: child,
            ),
            child: Image.file(File(path), fit: BoxFit.contain),
          ),
        ),
        const ColoredBox(color: Colors.black38),
        const Center(
          child: CircularProgressIndicator(
            key: ValueKey('captureProcessingIndicator'),
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

/// The cropped, perspective-corrected page shown after processing, filling
/// the preview so the user sees the final document (background already
/// gone) before the live camera returns for the next shot.
class _ProcessedResultPreview extends StatelessWidget {
  const _ProcessedResultPreview({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Stack(
      key: const ValueKey('captureResultPreview'),
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.88, end: 1),
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          builder: (context, t, child) =>
              Transform.scale(scale: t, child: child),
          child: Image.file(File(path), fit: BoxFit.contain),
        ),
      ],
    );
  }
}

class _PermissionRationale extends StatelessWidget {
  const _PermissionRationale({
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.cameraOff, color: Colors.white70, size: 56),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              key: const ValueKey('capturePermissionAction'),
              onPressed: onAction,
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _LivePreview extends StatelessWidget {
  const _LivePreview({
    required this.textureId,
    this.preview,
    required this.aspectRatio,
    required this.analysis,
    required this.focusIndicator,
    required this.showGrid,
    required this.onTapFocus,
  });

  final int? textureId;
  final Widget? preview;
  final double aspectRatio;
  final FrameAnalysis? analysis;
  final Offset? focusIndicator;
  final bool showGrid;
  final Future<void> Function(double x, double y) onTapFocus;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final parent = Size(constraints.maxWidth, constraints.maxHeight);
        final fitted = fittedPreviewRect(parent, aspectRatio);
        return Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Colors.black),
            Positioned.fromRect(
              rect: fitted,
              child: GestureDetector(
                key: const ValueKey('captureTapToFocus'),
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) {
                  final size = fitted.size;
                  if (size.width <= 0 || size.height <= 0) return;
                  onTapFocus(
                    (details.localPosition.dx / size.width).clamp(0.0, 1.0),
                    (details.localPosition.dy / size.height).clamp(0.0, 1.0),
                  );
                },
                child: CameraPreviewView(
                  textureId: textureId,
                  preview: preview,
                  aspectRatio: aspectRatio,
                  letterbox: false,
                ),
              ),
            ),
            Positioned.fromRect(
              rect: fitted,
              child: _DetectedPolygonOverlay(analysis: analysis),
            ),
            if (showGrid)
              Positioned.fromRect(
                rect: fitted,
                child: const IgnorePointer(
                  child: CustomPaint(
                    painter: _GridPainter(),
                    size: Size.infinite,
                  ),
                ),
              ),
            if (!_hasLiveQuad(analysis))
              Positioned.fromRect(
                rect: fitted,
                child: const _CaptureFrameGuide(),
              ),
            if (focusIndicator != null)
              Positioned(
                left: fitted.left + focusIndicator!.dx * fitted.width - 20,
                top: fitted.top + focusIndicator!.dy * fitted.height - 20,
                child: const IgnorePointer(
                  child: SizedBox(
                    key: ValueKey('captureFocusIndicator'),
                    width: 40,
                    height: 40,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.fromBorderSide(
                          BorderSide(color: Colors.yellowAccent, width: 2),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

bool _hasLiveQuad(FrameAnalysis? analysis) {
  final quad = analysis?.quad;
  return analysis != null &&
      quad != null &&
      analysis.confidence >= DetectionThresholds.minConfidence;
}

class _GridPainter extends CustomPainter {
  const _GridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
    for (var i = 1; i <= 2; i++) {
      final x = size.width * i / 3;
      final y = size.height * i / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Static alignment brackets. Color does not go green — a confident
/// detection draws [_DetectedPolygonOverlay] instead.
class _CaptureFrameGuide extends StatelessWidget {
  const _CaptureFrameGuide();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: CustomPaint(
        key: ValueKey('captureFrameGuide'),
        painter: _CaptureFrameGuidePainter(),
        size: Size.infinite,
      ),
    );
  }
}

class _CaptureFrameGuidePainter extends CustomPainter {
  const _CaptureFrameGuidePainter();

  static const _armLength = 28.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTRB(
      size.width * _guideHorizontalInset,
      size.height * _guideVerticalInset,
      size.width * (1 - _guideHorizontalInset),
      size.height * (1 - _guideVerticalInset),
    );
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    void bracket(Offset corner, Offset armX, Offset armY) {
      canvas.drawLine(corner, corner + armX, paint);
      canvas.drawLine(corner, corner + armY, paint);
    }

    bracket(
      rect.topLeft,
      const Offset(_armLength, 0),
      const Offset(0, _armLength),
    );
    bracket(
      rect.topRight,
      const Offset(-_armLength, 0),
      const Offset(0, _armLength),
    );
    bracket(
      rect.bottomLeft,
      const Offset(_armLength, 0),
      const Offset(0, -_armLength),
    );
    bracket(
      rect.bottomRight,
      const Offset(-_armLength, 0),
      const Offset(0, -_armLength),
    );
  }

  @override
  bool shouldRepaint(covariant _CaptureFrameGuidePainter oldDelegate) => false;
}

class _DetectedPolygonOverlay extends StatelessWidget {
  const _DetectedPolygonOverlay({required this.analysis});

  final FrameAnalysis? analysis;

  @override
  Widget build(BuildContext context) {
    final analysis = this.analysis;
    final quad = analysis?.quad;
    final show = _hasLiveQuad(analysis);
    if (!show) return const SizedBox.shrink();
    return IgnorePointer(
      child: CustomPaint(
        key: const ValueKey('captureDetectedPolygon'),
        painter: _DetectedPolygonPainter(
          quad: quad!,
          stable: analysis!.cornersStable,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _DetectedPolygonPainter extends CustomPainter {
  _DetectedPolygonPainter({required this.quad, required this.stable});

  final Quad quad;
  final bool stable;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(quad.topLeft.x * size.width, quad.topLeft.y * size.height)
      ..lineTo(quad.topRight.x * size.width, quad.topRight.y * size.height)
      ..lineTo(
        quad.bottomRight.x * size.width,
        quad.bottomRight.y * size.height,
      )
      ..lineTo(quad.bottomLeft.x * size.width, quad.bottomLeft.y * size.height)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = AppTheme.accent.withValues(alpha: 0.28)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = AppTheme.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant _DetectedPolygonPainter oldDelegate) =>
      oldDelegate.quad != quad || oldDelegate.stable != stable;
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({
    required this.analysis,
    required this.l10n,
    this.shutterHint,
  });

  final FrameAnalysis? analysis;
  final AppLocalizations l10n;
  final String? shutterHint;

  @override
  Widget build(BuildContext context) {
    final warnings = analysis?.warnings ?? const {};
    final warningText = warnings
        .map(_messageFor)
        .where((m) => m.isNotEmpty)
        .toList();
    final hint = switch (shutterHint) {
      'focusing' => l10n.captureFocusing,
      'holdStill' => l10n.captureHoldStill,
      _ => null,
    };
    final message = warningText.isNotEmpty ? warningText.first : hint;
    if (message == null) return const SizedBox.shrink();
    final isHold = warningText.isEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Material(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isHold) ...[
                const Icon(
                  LucideIcons.triangleAlert,
                  color: Colors.amber,
                  size: 20,
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  message,
                  style: const TextStyle(color: Colors.white),
                  semanticsLabel: message,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _messageFor(QualityWarning warning) => switch (warning) {
    QualityWarning.blur => l10n.captureWarningBlur,
    QualityWarning.glare => l10n.captureWarningGlare,
    QualityWarning.lowLight => l10n.captureWarningLowLight,
    QualityWarning.clippedEdges => l10n.captureWarningClippedEdges,
    QualityWarning.severeSkew => l10n.captureWarningSevereSkew,
    QualityWarning.fingerCovering => l10n.captureWarningFinger,
    QualityWarning.none => '',
  };
}

class _CaptureControls extends StatelessWidget {
  const _CaptureControls({
    required this.pageCount,
    required this.capturing,
    required this.lastPagePreviewPath,
    required this.isBook,
    required this.isIdScan,
    required this.l10n,
    required this.onShutter,
    required this.onDone,
    required this.onImport,
  });

  final int pageCount;
  final bool capturing;
  final String? lastPagePreviewPath;
  final bool isBook;
  final bool isIdScan;
  final AppLocalizations l10n;
  final VoidCallback onShutter;
  final VoidCallback onDone;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final scanningBack = isIdScan && pageCount > 0;
    final title = isIdScan
        ? (scanningBack ? l10n.scanIdBackTitle : l10n.scanIdFrontTitle)
        : (isBook ? l10n.captureReadyBookTitle : l10n.captureReadyTitle);
    final body = isIdScan
        ? (scanningBack ? l10n.scanIdBackBody : l10n.scanIdFrontBody)
        : (isBook ? l10n.captureReadyBookBody : l10n.captureReadyBody);
    final shutterLabel = isIdScan
        ? (scanningBack ? l10n.scanIdBackButton : l10n.scanIdFrontButton)
        : l10n.captureStartScanning;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              height: 1.35,
            ),
          ),
          if (pageCount > 0) ...[
            const SizedBox(height: 8),
            Text(
              l10n.pagesScanned(pageCount),
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              key: const ValueKey('shutterButton'),
              onPressed: capturing ? null : onShutter,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: const Color(0xFF04140C),
                disabledBackgroundColor: Colors.white24,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
              icon: const Icon(LucideIcons.scanLine),
              label: Text(
                shutterLabel,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  key: const ValueKey('captureImportButton'),
                  onPressed: capturing ? null : onImport,
                  icon: const Icon(LucideIcons.image, color: Colors.white),
                  label: Text(
                    l10n.captureImport,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              ),
              if (!isIdScan && pageCount > 0)
                Expanded(
                  child: _ContinueControl(
                    pageCount: pageCount,
                    previewPath: lastPagePreviewPath,
                    enabled: !capturing,
                    label: l10n.doneScanning,
                    onPressed: onDone,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ContinueControl extends StatelessWidget {
  const _ContinueControl({
    required this.pageCount,
    required this.previewPath,
    required this.enabled,
    required this.label,
    required this.onPressed,
  });

  final int pageCount;
  final String? previewPath;
  final bool enabled;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // TapScanner-style: big accent "Continue" callout above the last-page
    // thumb + count badge. Whole column is one tap target.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('captureDoneButton'),
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.accent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x66007AFF),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              CustomPaint(
                size: const Size(14, 7),
                painter: _ContinueCaretPainter(AppTheme.accent),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 44,
                          height: 52,
                          child: previewPath == null
                              ? const ColoredBox(color: Colors.white24)
                              : Image.file(
                                  File(previewPath!),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) =>
                                      const ColoredBox(color: Colors.white24),
                                ),
                        ),
                      ),
                      Positioned(
                        right: -4,
                        top: -4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.accent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$pageCount',
                            key: const ValueKey('capturePageCount'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 2),
                    child: Icon(
                      LucideIcons.chevronRight,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContinueCaretPainter extends CustomPainter {
  _ContinueCaretPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _ContinueCaretPainter oldDelegate) =>
      oldDelegate.color != color;
}
