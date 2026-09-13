import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../domain/models/geometry.dart';
import '../../../../domain/providers/page_detection_provider.dart';
import '../../../../domain/repositories/page_repository.dart';
import '../../../../domain/use_cases/capture_page_use_case.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../core/di/service_locator.dart';
import '../view_models/crop_correction_view_model.dart';

/// Manual four-corner crop/perspective-correction screen (SPEC 6.2, SPEC 12
/// acceptance criterion). Reached from Page Review; applying re-runs the
/// enhancement pipeline for just this page (SPEC 9.5: "Changing a crop or
/// filter invalidates only dependent stages").
class CropCorrectionScreen extends StatefulWidget {
  const CropCorrectionScreen({
    super.key,
    required this.projectId,
    required this.pageId,
    this.viewModel,
  });

  final String projectId;
  final String pageId;

  /// Injectable for widget tests; production code leaves this null.
  final CropCorrectionViewModel? viewModel;

  @override
  State<CropCorrectionScreen> createState() => _CropCorrectionScreenState();
}

class _CropCorrectionScreenState extends State<CropCorrectionScreen> {
  late final CropCorrectionViewModel _viewModel;

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

  Future<void> _apply() async {
    final ok = await _viewModel.apply();
    if (!mounted) return;
    if (ok) {
      context.pop();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${_viewModel.error}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(l10n.cropTitle),
        actions: [
          IconButton(
            key: const ValueKey('cropAutoDetectButton'),
            icon: const Icon(Icons.center_focus_weak),
            tooltip: l10n.cropAutoDetect,
            onPressed: _viewModel.resetToDetected,
          ),
          IconButton(
            key: const ValueKey('cropResetButton'),
            icon: const Icon(Icons.crop_free),
            tooltip: l10n.cropResetFullFrame,
            onPressed: _viewModel.resetToFullFrame,
          ),
        ],
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
              final fitted = applyBoxFit(BoxFit.contain, imageSize, available);
              final destSize = fitted.destination;
              final originX = (available.width - destSize.width) / 2;
              final originY = (available.height - destSize.height) / 2;
              final quad = _viewModel.quad;

              Offset screenPointFor(CropCorner corner) {
                final p = switch (corner) {
                  CropCorner.topLeft => quad.topLeft,
                  CropCorner.topRight => quad.topRight,
                  CropCorner.bottomRight => quad.bottomRight,
                  CropCorner.bottomLeft => quad.bottomLeft,
                };
                return Offset(
                  originX + p.x * destSize.width,
                  originY + p.y * destSize.height,
                );
              }

              return Stack(
                children: [
                  Positioned(
                    left: originX,
                    top: originY,
                    width: destSize.width,
                    height: destSize.height,
                    child: Image.file(
                      File(page.originalImagePath),
                      fit: BoxFit.fill,
                    ),
                  ),
                  Positioned(
                    left: originX,
                    top: originY,
                    width: destSize.width,
                    height: destSize.height,
                    child: IgnorePointer(
                      child: CustomPaint(painter: _QuadPainter(quad)),
                    ),
                  ),
                  for (final corner in CropCorner.values)
                    _CornerHandle(
                      key: ValueKey('cropHandle-${corner.name}'),
                      position: screenPointFor(corner),
                      onDrag: (delta) => _viewModel.dragCorner(
                        corner,
                        Offset(
                          delta.dx / destSize.width,
                          delta.dy / destSize.height,
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('cropCancelButton'),
                  onPressed: () => context.pop(),
                  child: Text(
                    l10n.cancel,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: FilledButton(
                  key: const ValueKey('cropApplyButton'),
                  onPressed: _viewModel.saving ? null : _apply,
                  child: _viewModel.saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(l10n.save),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CornerHandle extends StatelessWidget {
  const _CornerHandle({
    super.key,
    required this.position,
    required this.onDrag,
  });

  final Offset position;
  final ValueChanged<Offset> onDrag;

  static const double _touchTargetSize = 44;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx - _touchTargetSize / 2,
      top: position.dy - _touchTargetSize / 2,
      width: _touchTargetSize,
      height: _touchTargetSize,
      child: Semantics(
        label: 'Crop corner handle',
        child: GestureDetector(
          onPanUpdate: (details) => onDrag(details.delta),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: Colors.blueAccent, width: 3),
              boxShadow: const [
                BoxShadow(color: Colors.black45, blurRadius: 4),
              ],
            ),
            margin: const EdgeInsets.all(10),
          ),
        ),
      ),
    );
  }
}

class _QuadPainter extends CustomPainter {
  _QuadPainter(this.quad);

  final Quad quad;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.blueAccent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final fillPaint = Paint()
      ..color = Colors.blueAccent.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;

    Offset toOffset(Point2D p) => Offset(p.x * size.width, p.y * size.height);

    final path = Path()
      ..moveTo(toOffset(quad.topLeft).dx, toOffset(quad.topLeft).dy)
      ..lineTo(toOffset(quad.topRight).dx, toOffset(quad.topRight).dy)
      ..lineTo(toOffset(quad.bottomRight).dx, toOffset(quad.bottomRight).dy)
      ..lineTo(toOffset(quad.bottomLeft).dx, toOffset(quad.bottomLeft).dy)
      ..close();

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _QuadPainter oldDelegate) =>
      oldDelegate.quad != quad;
}
