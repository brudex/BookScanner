import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../domain/models/capture_models.dart';
import '../../../../domain/models/geometry.dart';
import '../../../../domain/providers/capture_provider.dart';
import '../../../../domain/repositories/page_repository.dart';
import '../../../../domain/repositories/project_repository.dart';
import '../../../../domain/use_cases/capture_page_use_case.dart';
import '../../../../domain/use_cases/process_book_spread_use_case.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../../routing/app_router.dart';
import '../../../core/di/service_locator.dart';
import '../view_models/capture_view_model.dart';
import '../preview_layout.dart';
import 'camera_preview_view.dart';

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
    this.viewModel,
  });

  final String projectId;

  /// When set, this session replaces exactly this page's image (the
  /// "Rescan" action from Page Review) instead of appending new pages.
  final String? replacePageId;
  final CaptureViewModel? viewModel;

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  late final CaptureViewModel _viewModel;

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
          replacePageId: widget.replacePageId,
          onNeedsCropCorrection: (pageId) {
            if (!mounted) return;
            context.push(AppRoutes.cropCorrectionFor(widget.projectId, pageId));
          },
        );
    _viewModel.initialize();
    _viewModel.addListener(_onViewModelChanged);
  }

  void _onViewModelChanged() {
    if (_viewModel.replacementComplete && mounted) {
      context.pop();
    }
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
      appBar: AppBar(
        title: Text(l10n.captureTitle),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
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
    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_viewModel.resultPreviewPath != null)
                _ProcessedResultPreview(path: _viewModel.resultPreviewPath!)
              else if (_viewModel.frozenPreviewPath != null)
                _FrozenCapturePreview(path: _viewModel.frozenPreviewPath!)
              else
                _LivePreview(
                  textureId: _viewModel.previewTextureId,
                  aspectRatio: _viewModel.previewAspectRatio,
                  analysis: _viewModel.latestAnalysis,
                  focusIndicator: _viewModel.focusIndicator,
                  onTapFocus: _viewModel.setFocusAndExposurePoint,
                ),
              if (_viewModel.capturing &&
                  _viewModel.frozenPreviewPath == null &&
                  _viewModel.resultPreviewPath == null)
                const _CaptureShutterScrim(),
              _WarningBanner(
                analysis: _viewModel.latestAnalysis,
                l10n: l10n,
                shutterHint: _viewModel.shutterHint,
                awaitingOverride: _viewModel.awaitingQualityOverride,
                onCaptureAnyway: () =>
                    _viewModel.captureManually(bypassQualityGate: true),
              ),
            ],
          ),
        ),
        _CaptureControls(
          pageCount: _viewModel.pageCount,
          capturing: _viewModel.capturing,
          flashMode: _viewModel.flashMode,
          zoomLevel: _viewModel.zoomLevel,
          shutterHint: _viewModel.shutterHint,
          l10n: l10n,
          onShutter: () => _viewModel.captureManually(),
          onFlash: _viewModel.cycleFlashMode,
          onZoom: _viewModel.setZoom,
          onDone: () async {
            await _viewModel.closeSession();
            if (!mounted) return;
            final name = await _promptScanName(this.context, l10n);
            if (!mounted) return;
            final trimmed = name?.trim();
            if (trimmed != null && trimmed.isNotEmpty) {
              await _viewModel.renameProject(trimmed);
            }
            if (!mounted) return;
            // `pushReplacement`, not `go`: `go` replaces the whole route
            // stack, stripping out everything below Capture (Library, and
            // for the "Add page" entry point, the prior Page Review
            // instance) so there was no way back from Review to the
            // project list afterward.
            this.context.pushReplacement(
              AppRoutes.pageReviewFor(widget.projectId),
            );
          },
        ),
      ],
    );
  }
}

/// Shown once when the user taps "Done" on a normal (non-rescan) capture
/// session, so a project doesn't stay stuck with its generic mode-based
/// default title ("Document"/"Book" -- see `NewScanSheetRoute`). Defaults
/// to a timestamp rather than leaving the field empty, since a name is
/// always required to be useful in the project list.
Future<String?> _promptScanName(BuildContext context, AppLocalizations l10n) =>
    showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _NameScanDialog(l10n: l10n),
    );

class _NameScanDialog extends StatefulWidget {
  const _NameScanDialog({required this.l10n});

  final AppLocalizations l10n;

  @override
  State<_NameScanDialog> createState() => _NameScanDialogState();
}

class _NameScanDialogState extends State<_NameScanDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: DateFormat('MM-dd HH:mm').format(DateTime.now()),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.l10n.nameScanTitle),
      content: TextField(
        key: const ValueKey('captureNameField'),
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: widget.l10n.nameScanLabel),
      ),
      actions: [
        TextButton(
          key: const ValueKey('captureNameCancelButton'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('captureNameSaveButton'),
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(widget.l10n.save),
        ),
      ],
    );
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
  const _FrozenCapturePreview({required this.path});

  final String path;

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
            tween: Tween(begin: 0, end: 1),
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
            const Icon(
              Icons.no_photography_outlined,
              color: Colors.white70,
              size: 56,
            ),
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
    required this.aspectRatio,
    required this.analysis,
    required this.focusIndicator,
    required this.onTapFocus,
  });

  final int? textureId;
  final double aspectRatio;
  final FrameAnalysis? analysis;
  final Offset? focusIndicator;
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
                  aspectRatio: aspectRatio,
                  letterbox: false,
                ),
              ),
            ),
            Positioned.fromRect(
              rect: fitted,
              child: _DetectedPolygonOverlay(analysis: analysis),
            ),
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
    final show =
        analysis != null &&
        quad != null &&
        analysis.confidence >= DetectionThresholds.minConfidence;
    if (!show) return const SizedBox.shrink();
    return IgnorePointer(
      child: CustomPaint(
        key: const ValueKey('captureDetectedPolygon'),
        painter: _DetectedPolygonPainter(
          quad: quad,
          stable: analysis.cornersStable,
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
    final paint = Paint()
      ..color = stable ? const Color(0xFF4CD964) : const Color(0xFFFFCC00)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawPath(path, paint);
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
    this.awaitingOverride = false,
    this.onCaptureAnyway,
  });

  final FrameAnalysis? analysis;
  final AppLocalizations l10n;
  final String? shutterHint;
  final bool awaitingOverride;
  final VoidCallback? onCaptureAnyway;

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
    if (message == null && !awaitingOverride) return const SizedBox.shrink();
    return Positioned(
      top: 16,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message != null)
                Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.amber,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        message,
                        style: const TextStyle(color: Colors.white),
                        semanticsLabel: message,
                      ),
                    ),
                  ],
                ),
              if (awaitingOverride) ...[
                const SizedBox(height: 8),
                TextButton(
                  key: const ValueKey('captureAnywayButton'),
                  onPressed: onCaptureAnyway,
                  child: Text(l10n.captureAnyway),
                ),
              ],
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
    required this.flashMode,
    required this.zoomLevel,
    required this.shutterHint,
    required this.l10n,
    required this.onShutter,
    required this.onDone,
    required this.onFlash,
    required this.onZoom,
  });

  final int pageCount;
  final bool capturing;
  final FlashMode flashMode;
  final double zoomLevel;
  final String? shutterHint;
  final AppLocalizations l10n;
  final VoidCallback onShutter;
  final VoidCallback onDone;
  final VoidCallback onFlash;
  final ValueChanged<double> onZoom;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
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
                  FlashMode.off => Icons.flash_off,
                  FlashMode.on => Icons.flash_on,
                  FlashMode.auto => Icons.flash_auto,
                  FlashMode.torch => Icons.highlight,
                }, color: Colors.white),
              ),
              Expanded(
                child: Slider(
                  key: const ValueKey('captureZoomSlider'),
                  value: zoomLevel,
                  onChanged: capturing ? null : onZoom,
                  semanticFormatterCallback: (_) => l10n.captureZoom,
                ),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.pagesScanned(pageCount),
                key: const ValueKey('capturePageCount'),
                style: const TextStyle(color: Colors.white),
              ),
              _ShutterButton(capturing: capturing, onPressed: onShutter),
              TextButton(
                key: const ValueKey('captureDoneButton'),
                onPressed: onDone,
                child: Text(
                  l10n.doneScanning,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.capturing, required this.onPressed});

  final bool capturing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Capture page',
      child: GestureDetector(
        key: const ValueKey('shutterButton'),
        onTap: capturing ? null : onPressed,
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
            color: capturing ? Colors.grey : Colors.white24,
          ),
          child: capturing
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 3,
                  ),
                )
              : null,
        ),
      ),
    );
  }
}
