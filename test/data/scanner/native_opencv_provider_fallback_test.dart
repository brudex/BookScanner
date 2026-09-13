import 'dart:io';

import 'package:bookscanner/data/services/scanner/adapters/native_opencv_page_detection_provider.dart';
import 'package:bookscanner/data/services/scanner/vision_platform_channel.dart';
import 'package:bookscanner/domain/models/geometry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'native OpenCV detector falls back to Dart when the plugin is missing',
    () async {
      final dir = await Directory.systemTemp.createTemp('opencv_fallback_');
      addTearDown(() => dir.delete(recursive: true));
      final image = img.Image(width: 400, height: 400);
      img.fill(image, color: img.ColorRgb8(30, 30, 30));
      img.fillRect(
        image,
        x1: 60,
        y1: 40,
        x2: 339,
        y2: 359,
        color: img.ColorRgb8(245, 245, 245),
      );
      final path = p.join(dir.path, 'page.jpg');
      File(path).writeAsBytesSync(img.encodeJpg(image, quality: 95));

      final provider = NativeOpenCvPageDetectionProvider(
        VisionPlatformChannel(),
      );
      final quad = await provider.detectQuad(path);

      expect(quad, isNotNull);
      expect(quad, isNot(Quad.fullFrame));
      expect(quad, isNot(Quad.captureGuide));
    },
  );
}
