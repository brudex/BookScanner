import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Renders the live camera preview. Prefers a plugin-owned preview widget
/// when the capture adapter supplies one (official `camera` package), and
/// otherwise uses Flutter's `Texture` with [textureId]. Falls back to a
/// placeholder when neither is available so manual capture remains usable
/// per SPEC 9.2.
class CameraPreviewView extends StatelessWidget {
  const CameraPreviewView({
    super.key,
    required this.textureId,
    this.preview,
    this.aspectRatio = 4 / 3,
    this.letterbox = true,
  });

  final int? textureId;

  /// Plugin-owned preview (e.g. official `CameraPreview`). Preferred over
  /// [textureId] when non-null so rotation/crop stay with the plugin.
  final Widget? preview;
  final double aspectRatio;

  /// When false, the texture fills the parent (parent already letterboxed).
  final bool letterbox;

  @override
  Widget build(BuildContext context) {
    final surface = preview ?? _textureOrPlaceholder();
    if (!letterbox) return surface;
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: aspectRatio <= 0 ? 4 / 3 : aspectRatio,
          child: surface,
        ),
      ),
    );
  }

  Widget _textureOrPlaceholder() {
    final id = textureId;
    if (id == null) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Icon(LucideIcons.camera, color: Colors.white38, size: 56),
        ),
      );
    }
    return Texture(textureId: id);
  }
}
