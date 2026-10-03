import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// One page image re-encoded for an export.
class EncodedPageImage {
  const EncodedPageImage(this.bytes, this.width, this.height);

  final Uint8List bytes;
  final int width;
  final int height;
}

/// Decodes the page at [path], applies EXIF orientation and
/// [rotationDegrees], fits it within [maxDimensionPx] and re-encodes it, all
/// on a background isolate. Returns null when the file cannot be decoded.
///
/// On Android, Dart runs on the app's main thread; decoding and encoding
/// a page there took seconds per page and froze the UI (ANR) during export.
Future<EncodedPageImage?> encodePageImage(
  String path, {
  int rotationDegrees = 0,
  int? maxDimensionPx,
  int jpegQuality = 85,
  bool png = false,
}) {
  return Isolate.run(() {
    final decoded = img.decodeImage(File(path).readAsBytesSync());
    if (decoded == null) return null;
    var oriented = img.bakeOrientation(decoded);
    if (rotationDegrees != 0) {
      oriented = img.copyRotate(oriented, angle: rotationDegrees);
    }
    if (maxDimensionPx != null) {
      final longest = oriented.width > oriented.height
          ? oriented.width
          : oriented.height;
      if (longest > maxDimensionPx) {
        oriented = oriented.width >= oriented.height
            ? img.copyResize(oriented, width: maxDimensionPx)
            : img.copyResize(oriented, height: maxDimensionPx);
      }
    }
    final bytes = png
        ? img.encodePng(oriented)
        : img.encodeJpg(oriented, quality: jpegQuality);
    return EncodedPageImage(bytes, oriented.width, oriented.height);
  });
}
