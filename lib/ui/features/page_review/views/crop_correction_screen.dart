import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../domain/models/geometry.dart';
import '../../../../domain/providers/page_detection_provider.dart';
import '../../../../domain/repositories/page_repository.dart';
import '../../../../domain/use_cases/capture_page_use_case.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../../routing/app_router.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/discard_unsaved_capture.dart';
import '../../../core/theme/app_theme.dart';
import '../view_models/crop_correction_view_model.dart';

/// Crop outline, handles, and Next — matches app green accent.
const _accent = AppTheme.accent;

/// How the crop screen continues after Next.
enum CropFlowMode {
  /// Opened from Page Review — Next applies and pops.
  review,

  /// Post-capture session — Next applies and opens filters for this page.
  postCapture,
}

/// Manual crop/perspective-correction screen. Handle model + gesture routing
/// mirror Tap Scanner's `SimpleCropImageView`: 4 corners + 4 edge midpoints +
/// drag inside the quad to move the whole frame. Image is inset so handles
/// are not pinned to the screen edge. Applying re-runs enhancement (SPEC 9.5).
class CropCorrectionScreen extends StatefulWidget {
  const CropCorrectionScreen({
    super.key,
    required this.projectId,
    required this.pageId,
    this.flowMode = CropFlowMode.review,
    this.viewModel,
  });

  final String projectId;
  final String pageId;
  final CropFlowMode flowMode;

  /// Injectable for widget tests; production code leaves this null.
  final CropCorrectionViewModel? viewModel;

  @override
  State<CropCorrectionScreen> createState() => _CropCorrectionScreenState();
}

class _CropCorrectionScreenState extends State<CropCorrectionScreen> {
  late final CropCorrectionViewModel _viewModel;

  CropHandle? _activeHandle;
  bool _movingQuad = false;

  static const double _cornerHitRadius = 40;
  static const double _strongCornerRadius = 28;
  static const double _edgeHitThickness = 52;

  /// Keep handles clear of bezels / gesture bars (Tap Scanner inset).
  static const double _canvasInset = 36;

  @override
  void initState() {
    super.initState();
    _viewModel =
        widget.viewModel ??
        CropCorrectionViewModel(
          pageId: widget.pageId,
          pageRepository: locator<PageRepository>(),
          capturePageUseCase: locator<CapturePageUseCase>(),
          detectionProvider: locator<PageDetectionProvider>(),
        );
    _viewModel.initialize();
  }

  @override
  void dispose() {
    if (widget.viewModel == null) _viewModel.dispose();
    super.dispose();
  }

  bool _leavingForward = false;

  Future<void> _discardAndLeave() async {
    if (widget.flowMode != CropFlowMode.postCapture) {
      if (mounted) context.pop();
      return;
    }
    await discardUnsavedCapture(widget.projectId);
    if (!mounted) return;
    context.go(AppRoutes.library);
  }

  Future<void> _onNext() async {
    _leavingForward = true;
    final ok = await _viewModel.apply();
    if (!mounted) return;
    if (!ok) {
      _leavingForward = false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${_viewModel.error}')));
      return;
    }
    if (widget.flowMode == CropFlowMode.postCapture) {
      context.pushReplacement(
        AppRoutes.postCaptureEditFor(widget.projectId),
        extra: widget.pageId,
      );
    } else {
      context.pop();
    }
  }

  static double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 < 1e-6) return (p - a).distance;
    var t = ((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / len2;
    t = t.clamp(0.0, 1.0);
    final proj = Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);
    return (p - proj).distance;
  }

  CropHandle? _hitTestHandle(Offset local, Size destSize) {
    Offset screen(Point2D p) =>
        Offset(p.x * destSize.width, p.y * destSize.height);
    final q = _viewModel.quad;

    // Strong corner grab first so corners stay precise near vertices.
    CropHandle? bestCorner;
    var bestCornerDist = _cornerHitRadius;
    for (final handle in const [
      CropHandle.topLeft,
      CropHandle.topRight,
      CropHandle.bottomRight,
      CropHandle.bottomLeft,
    ]) {
      final d = (screen(_viewModel.pointFor(handle)) - local).distance;
      if (d <= bestCornerDist) {
        bestCornerDist = d;
        bestCorner = handle;
      }
    }
    if (bestCorner != null && bestCornerDist <= _strongCornerRadius) {
      return bestCorner;
    }

    // Edge hit = distance to the full edge segment (not just the midpoint).
    CropHandle? bestEdge;
    var bestEdgeDist = _edgeHitThickness;
    void considerEdge(CropHandle handle, Point2D a, Point2D b) {
      final d = _distanceToSegment(local, screen(a), screen(b));
      if (d < bestEdgeDist) {
        bestEdgeDist = d;
        bestEdge = handle;
      }
    }

    considerEdge(CropHandle.top, q.topLeft, q.topRight);
    considerEdge(CropHandle.right, q.topRight, q.bottomRight);
    considerEdge(CropHandle.bottom, q.bottomLeft, q.bottomRight);
    considerEdge(CropHandle.left, q.topLeft, q.bottomLeft);
    if (bestEdge != null) return bestEdge;

    return bestCorner;
  }

  bool _pointInQuad(Offset local, Quad quad, Size destSize) {
    Offset to(Point2D p) => Offset(p.x * destSize.width, p.y * destSize.height);
    final pts = [
      to(quad.topLeft),
      to(quad.topRight),
      to(quad.bottomRight),
      to(quad.bottomLeft),
    ];
    var signPositive = false;
    for (var i = 0; i < 4; i++) {
      final a = pts[i];
      final b = pts[(i + 1) % 4];
      final cross =
          (b.dx - a.dx) * (local.dy - a.dy) - (b.dy - a.dy) * (local.dx - a.dx);
      if (i == 0) {
        signPositive = cross >= 0;
      } else if ((cross >= 0) != signPositive) {
        return false;
      }
    }
    return true;
  }

  void _onPanStart(DragStartDetails details, Size destSize) {
    final local = details.localPosition;
    final handle = _hitTestHandle(local, destSize);
    if (handle != null) {
      HapticFeedback.selectionClick();
      setState(() {
        _activeHandle = handle;
        _movingQuad = false;
      });
      return;
    }
    if (_pointInQuad(local, _viewModel.quad, destSize)) {
      setState(() {
        _activeHandle = null;
        _movingQuad = true;
      });
    }
  }

  void _onPanUpdate(DragUpdateDetails details, Size destSize) {
    final delta = Offset(
      details.delta.dx / destSize.width,
      details.delta.dy / destSize.height,
    );
    if (_activeHandle != null) {
      _viewModel.dragHandle(_activeHandle!, delta);
    } else if (_movingQuad) {
      _viewModel.moveQuad(delta);
    }
  }

  void _onPanEnd() {
    if (_activeHandle != null || _movingQuad) {
      setState(() {
        _activeHandle = null;
        _movingQuad = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopScope(
      canPop: widget.flowMode != CropFlowMode.postCapture,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _leavingForward) return;
        if (widget.flowMode == CropFlowMode.postCapture) {
          await _discardAndLeave();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF1A1A1A),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1A1A1A),
          foregroundColor: Colors.white,
          elevation: 0,
          title: const SizedBox.shrink(),
          leading: IconButton(
            key: const ValueKey('cropBackButton'),
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              if (widget.flowMode == CropFlowMode.postCapture) {
                await _discardAndLeave();
              } else {
                context.pop();
              }
            },
          ),
        ),
        body: ListenableBuilder(
          listenable: _viewModel,
          builder: (context, _) {
            if (_viewModel.loading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (_viewModel.error != null && _viewModel.page == null) {
              return Center(
                child: Text(
                  '${_viewModel.error}',
                  style: const TextStyle(color: Colors.white),
                ),
              );
            }
            final page = _viewModel.page!;
            final imageSize = _viewModel.imageSize;
            if (imageSize == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return LayoutBuilder(
              builder: (context, constraints) {
                final available = Size(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );
                final inset = _canvasInset;
                final inner = Size(
                  math.max(0, available.width - inset * 2),
                  math.max(0, available.height - inset * 2),
                );
                final turns = _viewModel.displayQuarterTurns;
                final layoutImageSize = turns.isOdd
                    ? Size(imageSize.height, imageSize.width)
                    : imageSize;
                final fitted = applyBoxFit(
                  BoxFit.contain,
                  layoutImageSize,
                  inner,
                );
                final boxSize = fitted.destination;
                final originX = inset + (inner.width - boxSize.width) / 2;
                final originY = inset + (inner.height - boxSize.height) / 2;

                // Pre-rotation content size (RotatedBox child).
                final contentW = turns.isOdd ? boxSize.height : boxSize.width;
                final contentH = turns.isOdd ? boxSize.width : boxSize.height;
                final contentSize = Size(contentW, contentH);
                final quad = _viewModel.quad;

                Offset screenFor(Point2D p) {
                  // Handles sit in the rotated child's local space; convert to
                  // parent stack coords via the same RotatedBox transform.
                  final local = Offset(p.x * contentW, p.y * contentH);
                  final centered = local - Offset(contentW / 2, contentH / 2);
                  final rotated = _rotateOffset(centered, turns);
                  return Offset(
                    originX + boxSize.width / 2 + rotated.dx,
                    originY + boxSize.height / 2 + rotated.dy,
                  );
                }

                return Stack(
                  children: [
                    Positioned(
                      left: originX,
                      top: originY,
                      width: boxSize.width,
                      height: boxSize.height,
                      child: Center(
                        child: RotatedBox(
                          quarterTurns: turns,
                          child: SizedBox(
                            width: contentW,
                            height: contentH,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.file(
                                  File(page.originalImagePath),
                                  fit: BoxFit.fill,
                                ),
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onPanStart: (d) =>
                                      _onPanStart(d, contentSize),
                                  onPanUpdate: (d) =>
                                      _onPanUpdate(d, contentSize),
                                  onPanEnd: (_) => _onPanEnd(),
                                  onPanCancel: _onPanEnd,
                                  child: CustomPaint(
                                    painter: _CropOverlayPainter(quad),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Handles drawn in parent space so they stay circular
                    // (not skewed by RotatedBox).
                    for (final handle in CropHandle.values)
                      _CropHandleVisual(
                        key: ValueKey('cropHandle-${handle.name}'),
                        position: screenFor(_viewModel.pointFor(handle)),
                        isActive: _activeHandle == handle,
                        isEdge: _isEdge(handle),
                      ),
                  ],
                );
              },
            );
          },
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 12, 12),
            child: ListenableBuilder(
              listenable: _viewModel,
              builder: (context, _) {
                return Row(
                  children: [
                    _CropFooterAction(
                      key: const ValueKey('cropRotateLeftButton'),
                      icon: LucideIcons.rotateCcw,
                      label: l10n.cropRotateLeft,
                      onPressed: _viewModel.rotateLeft,
                    ),
                    _CropFooterAction(
                      key: const ValueKey('cropRotateRightButton'),
                      icon: LucideIcons.rotateCw,
                      label: l10n.cropRotateRight,
                      onPressed: _viewModel.rotateRight,
                    ),
                    _CropFooterAction(
                      key: const ValueKey('cropNoCropButton'),
                      icon: LucideIcons.maximize2,
                      label: l10n.cropNoCrop,
                      onPressed: _viewModel.resetToFullFrame,
                    ),
                    const Spacer(),
                    FilledButton(
                      key: const ValueKey('cropNextButton'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: _viewModel.saving ? null : _onNext,
                      child: _viewModel.saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  l10n.cropNext,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(LucideIcons.chevronRight, size: 18),
                              ],
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  static Offset _rotateOffset(Offset p, int quarterTurns) {
    switch (quarterTurns % 4) {
      case 1:
        return Offset(-p.dy, p.dx);
      case 2:
        return Offset(-p.dx, -p.dy);
      case 3:
        return Offset(p.dy, -p.dx);
      default:
        return p;
    }
  }

  static bool _isEdge(CropHandle handle) =>
      handle == CropHandle.top ||
      handle == CropHandle.right ||
      handle == CropHandle.bottom ||
      handle == CropHandle.left;
}

class _CropFooterAction extends StatelessWidget {
  const _CropFooterAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

/// Non-interactive handle decoration. Hit-testing lives on the image canvas.
class _CropHandleVisual extends StatelessWidget {
  const _CropHandleVisual({
    super.key,
    required this.position,
    required this.isActive,
    required this.isEdge,
  });

  final Offset position;
  final bool isActive;
  final bool isEdge;

  @override
  Widget build(BuildContext context) {
    final visualSize = isActive
        ? (isEdge ? 26.0 : 28.0)
        : (isEdge ? 20.0 : 22.0);
    return Positioned(
      left: position.dx - visualSize / 2,
      top: position.dy - visualSize / 2,
      width: visualSize,
      height: visualSize,
      child: IgnorePointer(
        child: Semantics(
          label: isEdge ? 'Crop edge handle' : 'Crop corner handle',
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: visualSize,
            height: visualSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? _accent : Colors.white,
              border: Border.all(
                color: isActive ? Colors.white : _accent,
                width: isActive ? 3 : 2.5,
              ),
              boxShadow: const [
                BoxShadow(color: Colors.black54, blurRadius: 6),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dims everything outside the crop quad and outlines the quad.
class _CropOverlayPainter extends CustomPainter {
  _CropOverlayPainter(this.quad);

  final Quad quad;

  @override
  void paint(Canvas canvas, Size size) {
    Offset toOffset(Point2D p) => Offset(p.x * size.width, p.y * size.height);

    final quadPath = Path()
      ..moveTo(toOffset(quad.topLeft).dx, toOffset(quad.topLeft).dy)
      ..lineTo(toOffset(quad.topRight).dx, toOffset(quad.topRight).dy)
      ..lineTo(toOffset(quad.bottomRight).dx, toOffset(quad.bottomRight).dy)
      ..lineTo(toOffset(quad.bottomLeft).dx, toOffset(quad.bottomLeft).dy)
      ..close();

    final fullPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final maskPath = Path.combine(PathOperation.difference, fullPath, quadPath);

    canvas.drawPath(
      maskPath,
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );

    canvas.drawPath(
      quadPath,
      Paint()
        ..color = _accent
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter oldDelegate) =>
      oldDelegate.quad != quad;
}
