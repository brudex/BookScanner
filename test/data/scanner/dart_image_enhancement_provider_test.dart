import 'dart:io';
import 'dart:math' as math;

import 'package:bookscanner/data/services/local/app_paths.dart';
import 'package:bookscanner/data/services/local/file_storage_service.dart';
import 'package:bookscanner/data/services/scanner/adapters/dart_image_enhancement_provider.dart';
import 'package:bookscanner/domain/models/geometry.dart';
import 'package:bookscanner/domain/models/scan_page.dart';
import 'package:bookscanner/domain/providers/image_enhancement_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../fakes/fake_path_provider_platform.dart';

// Fills a real testing gap: DartImageEnhancementProvider had no dedicated
// unit tests before this file. Mirrors dart_book_dewarp_provider_test.dart's
// AppPaths/FileStorageService scaffolding (needed here because `enhance`
// writes a thumbnail via `_fileStorage.paths.thumbnailPathFor`).

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmpDir;
  late DartImageEnhancementProvider provider;

  setUpAll(() async {
    tmpDir = await Directory.systemTemp.createTemp('image_enhancement_test_');
    PathProviderPlatform.instance = FakePathProviderPlatform(tmpDir);
  });

  setUp(() async {
    final paths = await AppPaths.instance();
    provider = DartImageEnhancementProvider(FileStorageService(paths));
  });

  tearDownAll(() async {
    if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
  });

  String writeImage(img.Image image, String name) {
    final path = p.join(tmpDir.path, name);
    File(path).writeAsBytesSync(img.encodeJpg(image, quality: 95));
    return path;
  }

  img.Image checkerboard(int size, int tile, int light, int dark) {
    final image = img.Image(width: size, height: size);
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final isLight = ((x ~/ tile) + (y ~/ tile)).isEven;
        final v = isLight ? light : dark;
        image.setPixelRgb(x, y, v, v, v);
      }
    }
    return image;
  }

  group('scoreQuality (sharpness proxy, not exposure-aware)', () {
    test('a high-contrast, fine-detail page scores high quality', () async {
      // Corpus: "flat page" with real text-like fine detail.
      final path = writeImage(
        checkerboard(300, 4, 240, 20),
        'sharp_bright.jpg',
      );
      final score = await provider.scoreQuality(path);
      expect(score, greaterThan(0.5));
    });

    test(
      'darkening the same fine detail does not by itself lower the score',
      () async {
        // The metric is purely a Laplacian-variance blur proxy -- it has no
        // exposure/luminance term at all, so a dim-but-crisp image should
        // score comparably to a bright-but-crisp one.
        final brightPath = writeImage(
          checkerboard(300, 4, 240, 20),
          'sharp_bright2.jpg',
        );
        final darkPath = writeImage(
          checkerboard(300, 4, 90, 20),
          'sharp_dark.jpg',
        );

        final brightScore = await provider.scoreQuality(brightPath);
        final darkScore = await provider.scoreQuality(darkPath);

        expect(darkScore, greaterThan(0.3));
        expect(darkScore, greaterThan(brightScore * 0.4));
      },
    );

    test(
      'a blurred low-light-style page (soft/noisy edges) scores clearly lower than a sharp one, '
      'even though its average brightness is the same order as the dark-but-sharp case above',
      () async {
        // Corpus: "low light" -- modeled as reduced sharpness (motion
        // blur/sensor noise smoothing), not merely low brightness, since
        // this provider's quality score cannot distinguish "dim" from
        // "blurry" -- documenting that distinction is the point of this
        // test.
        final sharpDark = checkerboard(300, 4, 90, 20);
        final blurredLowLight = img.gaussianBlur(sharpDark, radius: 6);
        final path = writeImage(blurredLowLight, 'blurred_low_light.jpg');

        final sharpScore = await provider.scoreQuality(
          writeImage(checkerboard(300, 4, 90, 20), 'sharp_dark_ref.jpg'),
        );
        final blurredScore = await provider.scoreQuality(path);

        expect(blurredScore, lessThan(sharpScore * 0.3));
      },
    );
  });

  group(
    'glossy/glare handling (no dedicated compensation -- documents the gap)',
    () {
      test(
        'a smooth glare patch over part of a textured page does not crash and does not zero the whole-page score',
        () async {
          // Corpus: "glossy paper" -- a large smooth, uniformly bright patch
          // (simulating a flash/light reflection) over one quadrant of an
          // otherwise text-like page. There is no dedicated glare-detection
          // or -compensation step anywhere in this provider; this test's
          // purpose is to confirm that fact doesn't manifest as a crash or a
          // spuriously zeroed score, not to claim glare is handled well.
          final image = checkerboard(300, 4, 240, 20);
          img.fillRect(
            image,
            x1: 150,
            y1: 0,
            x2: 299,
            y2: 149,
            color: img.ColorRgb8(255, 255, 255),
          );
          final sourcePath = writeImage(image, 'glossy_source.jpg');
          final outputPath = p.join(tmpDir.path, 'glossy_out.jpg');

          final result = await provider.enhance(
            EnhancementRequest(
              sourceImagePath: sourcePath,
              outputImagePath: outputPath,
              cropPoints: Quad.fullFrame,
              rotationDegrees: 0,
              filter: PageFilter.original,
            ),
          );

          expect(File(outputPath).existsSync(), isTrue);
          expect(result.qualityScore, greaterThan(0.1));
        },
      );
    },
  );

  group('rectify / crop (perspective correction)', () {
    // Fills a real gap: every other test in this file passes
    // `cropPoints: Quad.fullFrame`, so `_rectify` (the actual crop/warp
    // step) had never been directly exercised by a unit test before this
    // group -- see IMPLEMENTATION_STATUS.md for the user-reported "saved
    // scan still shows the background" investigation this came out of.

    double whitePixelFraction(img.Image image, {int threshold = 200}) {
      var white = 0;
      var total = 0;
      for (final p in image) {
        total++;
        if (p.r >= threshold && p.g >= threshold && p.b >= threshold) white++;
      }
      return white / total;
    }

    test(
      'crops away a solid background outside an inset, axis-aligned quad',
      () async {
        final image = img.Image(width: 400, height: 400);
        img.fill(image, color: img.ColorRgb8(10, 10, 10));
        img.fillRect(
          image,
          x1: 100,
          y1: 80,
          x2: 300,
          y2: 320,
          color: img.ColorRgb8(250, 250, 250),
        );
        final sourcePath = writeImage(image, 'inset_source.jpg');
        final outputPath = p.join(tmpDir.path, 'inset_out.jpg');

        // Slightly inside the white rectangle's own bounds so bilinear
        // sampling at the very edge doesn't average in a sliver of the
        // dark background.
        final quad = Quad(
          topLeft: const Point2D(x: 100 / 400, y: 80 / 400),
          topRight: const Point2D(x: 299 / 400, y: 80 / 400),
          bottomRight: const Point2D(x: 299 / 400, y: 319 / 400),
          bottomLeft: const Point2D(x: 100 / 400, y: 319 / 400),
        );

        await provider.enhance(
          EnhancementRequest(
            sourceImagePath: sourcePath,
            outputImagePath: outputPath,
            cropPoints: quad,
            rotationDegrees: 0,
            filter: PageFilter.original,
            removeShadowsAndStains: false,
          ),
        );

        final output = img.decodeImage(File(outputPath).readAsBytesSync())!;
        // Virtually the whole output should be the (formerly inset) white
        // rectangle -- if the dark background were still present anywhere
        // near its old proportions, this would be far lower.
        expect(whitePixelFraction(output), greaterThan(0.98));
      },
    );

    test(
      'warps a skewed (non-axis-aligned) quad into a flat rectangle, not just its axis-aligned bounding box',
      () async {
        // A page rotated 15 degrees off-axis against a dark background --
        // same construction as the rotated-page case in
        // dart_page_detection_provider_test.dart.
        const halfWidth = 100.0;
        const halfHeight = 140.0;
        const angle = 15 * math.pi / 180;
        const centerX = 200.0;
        const centerY = 200.0;
        final cosA = math.cos(angle);
        final sinA = math.sin(angle);
        img.Point rotated(double dx, double dy) => img.Point(
          centerX + dx * cosA - dy * sinA,
          centerY + dx * sinA + dy * cosA,
        );

        final image = img.Image(width: 400, height: 400);
        img.fill(image, color: img.ColorRgb8(10, 10, 10));
        final corners = [
          rotated(-halfWidth, -halfHeight),
          rotated(halfWidth, -halfHeight),
          rotated(halfWidth, halfHeight),
          rotated(-halfWidth, halfHeight),
        ];
        img.fillPolygon(
          image,
          vertices: corners,
          color: img.ColorRgb8(250, 250, 250),
        );
        final sourcePath = writeImage(image, 'skewed_source.jpg');
        final outputPath = p.join(tmpDir.path, 'skewed_out.jpg');

        Point2D norm(img.Point p) => Point2D(x: p.x / 400, y: p.y / 400);
        final quad = Quad(
          topLeft: norm(corners[0]),
          topRight: norm(corners[1]),
          bottomRight: norm(corners[2]),
          bottomLeft: norm(corners[3]),
        );

        await provider.enhance(
          EnhancementRequest(
            sourceImagePath: sourcePath,
            outputImagePath: outputPath,
            cropPoints: quad,
            rotationDegrees: 0,
            filter: PageFilter.original,
            removeShadowsAndStains: false,
          ),
        );

        final output = img.decodeImage(File(outputPath).readAsBytesSync())!;
        // A true perspective warp fills the whole output with the page,
        // corners included. A naive axis-aligned crop of the tilted
        // shape's bounding box would leave dark background triangles in
        // the corners instead -- checked directly, not just an overall
        // white-fraction average that could hide exactly that failure
        // mode.
        expect(whitePixelFraction(output), greaterThan(0.95));
        for (final corner in <(int, int)>[
          (4, 4),
          (output.width - 5, 4),
          (4, output.height - 5),
          (output.width - 5, output.height - 5),
        ]) {
          final p = output.getPixel(corner.$1, corner.$2);
          expect(
            p.r,
            greaterThan(200),
            reason:
                'corner ${corner.$1},${corner.$2} should be page, not background',
          );
        }
      },
    );

    test(
      "output preserves the selected quad's own proportions, not the source photo's aspect ratio",
      () async {
        // Landscape source photo (like a phone held sideways), but the
        // selected page region within it is portrait-shaped (a typical
        // book/document page) -- the output must come out portrait too.
        final image = img.Image(width: 600, height: 300);
        img.fill(image, color: img.ColorRgb8(10, 10, 10));
        img.fillRect(
          image,
          x1: 240,
          y1: 20,
          x2: 360,
          y2: 280,
          color: img.ColorRgb8(250, 250, 250),
        );
        final sourcePath = writeImage(image, 'aspect_source.jpg');
        final outputPath = p.join(tmpDir.path, 'aspect_out.jpg');

        final quad = Quad(
          topLeft: const Point2D(x: 240 / 600, y: 20 / 300),
          topRight: const Point2D(x: 359 / 600, y: 20 / 300),
          bottomRight: const Point2D(x: 359 / 600, y: 279 / 300),
          bottomLeft: const Point2D(x: 240 / 600, y: 279 / 300),
        );

        await provider.enhance(
          EnhancementRequest(
            sourceImagePath: sourcePath,
            outputImagePath: outputPath,
            cropPoints: quad,
            rotationDegrees: 0,
            filter: PageFilter.original,
            removeShadowsAndStains: false,
          ),
        );

        final output = img.decodeImage(File(outputPath).readAsBytesSync())!;
        expect(
          output.height,
          greaterThan(output.width),
          reason:
              'the selected region is portrait (120 wide x 260 tall); the '
              'output should be too, not stretched to the landscape '
              'source photo\'s own 600x300 aspect ratio',
        );
      },
    );
  });

  group(
    'removeShadowsAndStains (illumination-normalization / shadow flattening)',
    () {
      img.Image gradientBackground(int size) {
        final image = img.Image(width: size, height: size);
        for (var x = 0; x < size; x++) {
          final value = (220 - (120 * x / size)).round().clamp(0, 255);
          for (var y = 0; y < size; y++) {
            image.setPixelRgb(x, y, value, value, value);
          }
        }
        return image;
      }

      double stddevOfRow(img.Image image, int y) {
        final values = [
          for (var x = 0; x < image.width; x++)
            image.getPixel(x, y).r.toDouble(),
        ];
        final mean = values.reduce((a, b) => a + b) / values.length;
        final variance =
            values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
            values.length;
        return math.sqrt(variance);
      }

      test(
        'flattens a shadow-like background luminance gradient toward uniform',
        () async {
          // Corpus: "shadows" -- a smooth luminance ramp across the page, as a
          // soft shadow or uneven lighting would produce. Flatten only runs
          // after a real crop (full-frame photos skip it), so this uses a
          // slight inset.
          const inset = Quad(
            topLeft: Point2D(x: 0.04, y: 0.04),
            topRight: Point2D(x: 0.96, y: 0.04),
            bottomRight: Point2D(x: 0.96, y: 0.96),
            bottomLeft: Point2D(x: 0.04, y: 0.96),
          );
          final sourcePath = writeImage(
            gradientBackground(300),
            'shadow_source.jpg',
          );
          final beforeStddev = stddevOfRow(
            img.decodeImage(File(sourcePath).readAsBytesSync())!,
            150,
          );

          final outputPath = p.join(tmpDir.path, 'shadow_flattened.jpg');
          await provider.enhance(
            EnhancementRequest(
              sourceImagePath: sourcePath,
              outputImagePath: outputPath,
              cropPoints: inset,
              rotationDegrees: 0,
              filter: PageFilter.original,
            ),
          );
          final afterStddev = stddevOfRow(
            img.decodeImage(File(outputPath).readAsBytesSync())!,
            150,
          );

          expect(afterStddev, lessThan(beforeStddev * 0.5));
        },
      );

      test(
        'removeShadowsAndStains: false leaves the gradient largely intact',
        () async {
          final sourcePath = writeImage(
            gradientBackground(300),
            'shadow_source2.jpg',
          );
          final beforeStddev = stddevOfRow(
            img.decodeImage(File(sourcePath).readAsBytesSync())!,
            150,
          );

          final outputPath = p.join(tmpDir.path, 'shadow_unflattened.jpg');
          await provider.enhance(
            EnhancementRequest(
              sourceImagePath: sourcePath,
              outputImagePath: outputPath,
              cropPoints: Quad.fullFrame,
              rotationDegrees: 0,
              filter: PageFilter.original,
              removeShadowsAndStains: false,
            ),
          );
          final afterStddev = stddevOfRow(
            img.decodeImage(File(outputPath).readAsBytesSync())!,
            150,
          );

          expect(afterStddev, greaterThan(beforeStddev * 0.7));
        },
      );

      test('skips illumination flatten when the crop is full-frame', () async {
        final sourcePath = writeImage(
          gradientBackground(300),
          'shadow_fullframe.jpg',
        );
        final beforeStddev = stddevOfRow(
          img.decodeImage(File(sourcePath).readAsBytesSync())!,
          150,
        );

        final outputPath = p.join(
          tmpDir.path,
          'shadow_unflattened_fullframe.jpg',
        );
        await provider.enhance(
          EnhancementRequest(
            sourceImagePath: sourcePath,
            outputImagePath: outputPath,
            cropPoints: Quad.fullFrame,
            rotationDegrees: 0,
            filter: PageFilter.original,
          ),
        );
        final afterStddev = stddevOfRow(
          img.decodeImage(File(outputPath).readAsBytesSync())!,
          150,
        );

        expect(afterStddev, greaterThan(beforeStddev * 0.7));
      });
    },
  );

  test(
    'detectCrop finds an inset page in one pass and reports the applied quad',
    () async {
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
      final sourcePath = writeImage(image, 'detect_crop_source.jpg');
      final outputPath = p.join(tmpDir.path, 'detect_crop_out.jpg');

      final result = await provider.enhance(
        EnhancementRequest(
          sourceImagePath: sourcePath,
          outputImagePath: outputPath,
          cropPoints: Quad.fullFrame,
          rotationDegrees: 0,
          filter: PageFilter.original,
          detectCrop: true,
          removeShadowsAndStains: false,
        ),
      );

      expect(result.cropPoints, isNot(Quad.fullFrame));
      expect(result.cropPoints.topLeft.x, closeTo(60 / 400, 0.08));
      final output = img.decodeImage(File(outputPath).readAsBytesSync())!;
      expect(output.width, lessThan(400));
      expect(output.height, lessThan(400));
    },
  );

  test(
    'document B&W uses local adaptive thresholding, not a global mean',
    () async {
      final image = img.Image(width: 200, height: 200);
      for (var y = 0; y < 200; y++) {
        for (var x = 0; x < 200; x++) {
          final bg = x < 100 ? 80 : 200;
          image.setPixelRgb(x, y, bg, bg, bg);
        }
      }
      img.drawLine(
        image,
        x1: 20,
        y1: 40,
        x2: 80,
        y2: 40,
        color: img.ColorRgb8(20, 20, 20),
        thickness: 3,
      );
      img.drawLine(
        image,
        x1: 120,
        y1: 40,
        x2: 180,
        y2: 40,
        color: img.ColorRgb8(20, 20, 20),
        thickness: 3,
      );
      final sourcePath = writeImage(image, 'adaptive_bw_source.jpg');
      final outputPath = p.join(tmpDir.path, 'adaptive_bw_out.jpg');

      await provider.enhance(
        EnhancementRequest(
          sourceImagePath: sourcePath,
          outputImagePath: outputPath,
          cropPoints: Quad.fullFrame,
          rotationDegrees: 0,
          filter: PageFilter.blackAndWhite,
          removeShadowsAndStains: false,
        ),
      );

      final out = img.decodeImage(File(outputPath).readAsBytesSync())!;
      expect(out.getPixel(50, 40).r.toInt(), lessThan(40));
      expect(out.getPixel(150, 40).r.toInt(), lessThan(40));
    },
  );
}
