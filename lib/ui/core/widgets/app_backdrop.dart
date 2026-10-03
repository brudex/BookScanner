import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Which mockup background to draw.
enum AppBackdropStyle {
  /// Home: glossy emerald swoosh across the top with a bright edge.
  home,

  /// Inner screens (Review, …): a soft diagonal light beam from the top
  /// right corner.
  inner,
}

/// The mockups' dark-emerald background, drawn in code.
///
/// Kept cheap: the artwork is painted once per (style, size) into a
/// half-resolution image on the raster thread, then every frame just draws
/// that image (no per-frame blur or gradient work). One copy is shared by
/// every screen of the same size; at most [_maxCached] are kept. Until the
/// image is ready (first frame), the plain base gradient is shown, which is
/// what the app showed before.
///
/// Fills its parent; put it behind a transparent [Scaffold] in a [Stack].
class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key, this.style = AppBackdropStyle.inner});

  final AppBackdropStyle style;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          if (!size.isFinite || size.isEmpty) {
            return const DecoratedBox(
              decoration: BoxDecoration(gradient: AppTheme.homeGradient),
            );
          }
          return _CachedBackdrop(style: style, size: size);
        },
      ),
    );
  }
}

/// Pixels per logical pixel for the cached image. The artwork is soft
/// gradients and blurs, so half the screen's density looks the same while
/// using a quarter of the memory (about 2.5 MB on a 1080 x 2400 phone).
const double _renderScale = 0.5;
const int _maxCached = 3;

typedef _Key = ({AppBackdropStyle style, int w, int h, int px});

final Map<_Key, Future<ui.Image>> _cache = {};

Future<ui.Image> _imageFor(_Key key) {
  final hit = _cache.remove(key);
  if (hit != null) {
    _cache[key] = hit; // most recently used last
    return hit;
  }
  final future = _render(key);
  _cache[key] = future;
  while (_cache.length > _maxCached) {
    // Evicted images are released by GC once no widget still shows them.
    _cache.remove(_cache.keys.first);
  }
  // A failed render is not cached; the gradient fallback stays visible.
  future.catchError((Object _) {
    _cache.remove(key);
    return future;
  });
  return future;
}

Future<ui.Image> _render(_Key key) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final scale = key.px / 100;
  canvas.scale(scale);
  _paintBackdrop(canvas, Size(key.w.toDouble(), key.h.toDouble()), key.style);
  final picture = recorder.endRecording();
  return picture
      .toImage((key.w * scale).ceil(), (key.h * scale).ceil())
      .whenComplete(picture.dispose);
}

class _CachedBackdrop extends StatefulWidget {
  const _CachedBackdrop({required this.style, required this.size});

  final AppBackdropStyle style;
  final Size size;

  @override
  State<_CachedBackdrop> createState() => _CachedBackdropState();
}

class _CachedBackdropState extends State<_CachedBackdrop> {
  ui.Image? _image;
  _Key? _key;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _CachedBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    _resolve();
  }

  void _resolve() {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2;
    final key = (
      style: widget.style,
      w: widget.size.width.round(),
      h: widget.size.height.round(),
      px: (dpr * _renderScale * 100).round(),
    );
    if (key == _key) return;
    _key = key;
    _imageFor(key).then((image) {
      if (mounted && _key == key) setState(() => _image = image);
    }, onError: (Object _) {});
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppTheme.homeGradient),
      child: image == null
          ? const SizedBox.expand()
          : RawImage(
              image: image,
              width: widget.size.width,
              height: widget.size.height,
              fit: BoxFit.fill,
              filterQuality: FilterQuality.medium,
            ),
    );
  }
}

/// Paints one backdrop. Runs once per (style, size), off the frame path.
void _paintBackdrop(Canvas canvas, Size size, AppBackdropStyle style) {
  final w = size.width;
  final h = size.height;
  final full = Offset.zero & size;

  // Base: the existing deep black -> emerald wash.
  canvas.drawRect(full, Paint()..shader = AppTheme.homeGradient.createShader(full));

  void glow(Offset center, double radius, Color color) {
    canvas.drawRect(
      full,
      Paint()
        ..shader = RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  switch (style) {
    case AppBackdropStyle.home:
      // Ambient light from the top right, as in the Home mockup.
      glow(
        Offset(w * 0.78, -h * 0.02),
        w * 0.95,
        AppTheme.accentDeep.withValues(alpha: 0.38),
      );
      glow(
        Offset(w * 0.05, h * 0.55),
        w * 0.75,
        AppTheme.accentDeep.withValues(alpha: 0.10),
      );

      // The swoosh: the region above a sweeping curve, brighter towards
      // the top right, with a soft edge.
      final edge = Path()
        ..moveTo(w * 0.18, -h * 0.02)
        ..cubicTo(w * 0.42, h * 0.10, w * 0.70, h * 0.04, w * 1.04, h * 0.16);
      final band = Path.from(edge)
        ..lineTo(w * 1.04, -h * 0.02)
        ..close();
      final bandRect = Rect.fromLTWH(0, 0, w, h * 0.18);
      canvas.drawPath(
        band,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              AppTheme.accent.withValues(alpha: 0.30),
              AppTheme.accentDeep.withValues(alpha: 0.10),
            ],
          ).createShader(bandRect)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
      );
      // Glossy rim along the curve: a wide soft glow plus a thin bright line.
      canvas.drawPath(
        edge,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 18
          ..color = AppTheme.accent.withValues(alpha: 0.12)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
      );
      canvas.drawPath(
        edge,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = AppTheme.accent.withValues(alpha: 0.55)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
      );
      // A fainter second wave below for depth.
      final wave = Path()
        ..moveTo(-w * 0.04, h * 0.10)
        ..cubicTo(w * 0.30, h * 0.20, w * 0.62, h * 0.12, w * 1.04, h * 0.27);
      canvas.drawPath(
        wave,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 26
          ..color = AppTheme.accent.withValues(alpha: 0.06)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
      );

    case AppBackdropStyle.inner:
      // A diagonal beam from the top right corner, as in the Review mockup.
      glow(
        Offset(w * 0.92, -h * 0.01),
        w * 0.70,
        AppTheme.accentDeep.withValues(alpha: 0.32),
      );
      final beam = Path()
        ..moveTo(w * 0.42, -h * 0.02)
        ..lineTo(w * 0.70, -h * 0.02)
        ..lineTo(w * 1.04, h * 0.10)
        ..lineTo(w * 1.04, h * 0.20)
        ..close();
      canvas.drawPath(
        beam,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              AppTheme.accent.withValues(alpha: 0.20),
              AppTheme.accent.withValues(alpha: 0.0),
            ],
          ).createShader(Rect.fromLTWH(w * 0.4, 0, w * 0.6, h * 0.2))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(12, w * 0.05)),
      );
  }

  // Gentle darkening towards the bottom keeps lists and buttons readable.
  canvas.drawRect(
    full,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, Colors.black.withValues(alpha: 0.30)],
        stops: const [0.55, 1.0],
      ).createShader(full),
  );
}
