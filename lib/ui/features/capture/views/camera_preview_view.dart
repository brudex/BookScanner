import 'package:flutter/material.dart';

/// Renders the native live preview using Flutter's built-in `Texture`
/// widget — never a vendor camera-preview widget (SPEC 9.1: "Render the
/// native preview efficiently with the supported Flutter texture/platform-
/// view mechanism"). Falls back to a neutral placeholder when no texture is
/// available (manual-only devices, or before the session finishes opening)
/// so manual capture remains usable per SPEC 9.2.
class CameraPreviewView extends StatelessWidget {
  const CameraPreviewView({
    super.key,
    required this.textureId,
    this.aspectRatio = 4 / 3,
    this.letterbox = true,
  });

  final int? textureId;
  final double aspectRatio;

  /// When false, the texture fills the parent (parent already letterboxed).
  final bool letterbox;

  @override
  Widget build(BuildContext context) {
    final id = textureId;
    if (id == null) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Icon(
            Icons.camera_alt_outlined,
            color: Colors.white38,
            size: 56,
          ),
        ),
      );
    }
    if (!letterbox) {
      return Texture(textureId: id);
    }
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: aspectRatio <= 0 ? 4 / 3 : aspectRatio,
          child: Texture(textureId: id),
        ),
      ),
    );
  }
}
