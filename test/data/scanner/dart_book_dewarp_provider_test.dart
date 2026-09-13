import 'dart:io';
import 'dart:math' as math;

import 'package:bookscanner/data/services/local/app_paths.dart';
import 'package:bookscanner/data/services/local/file_storage_service.dart';
import 'package:bookscanner/data/services/scanner/adapters/dart_book_dewarp_provider.dart';
import 'package:bookscanner/domain/models/geometry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../fakes/fake_path_provider_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmpDir;
  late FileStorageService fileStorage;
  late DartBookDewarpProvider provider;

  setUpAll(() async {
    tmpDir = await Directory.systemTemp.createTemp('book_dewarp_test_');
    PathProviderPlatform.instance = FakePathProviderPlatform(tmpDir);
  });

  setUp(() async {
    final paths = await AppPaths.instance();
    fileStorage = FileStorageService(paths);
    provider = DartBookDewarpProvider(fileStorage);
  });

  tearDownAll(() async {
    if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
  });

  String writeImage(img.Image image, String name) {
    final path = p.join(tmpDir.path, name);
    File(path).writeAsBytesSync(img.encodeJpg(image, quality: 95));
    return path;
  }

  group('splitSpread', () {
    test('detects a clear vertical gutter with high confidence', () async {
      final image = img.Image(width: 400, height: 300);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));
      // A solid dark gutter line at x=200, well inside the 35%-65% search
      // band (columns 140-260).
      img.fillRect(
        image,
        x1: 197,
        y1: 0,
        x2: 203,
        y2: 299,
        color: img.ColorRgb8(0, 0, 0),
      );
      final path = writeImage(image, 'clear_gutter.jpg');

      final result = await provider.splitSpread(path);

      expect(result.confidence, greaterThan(0.5));
      expect(File(result.leftPageImagePath).existsSync(), isTrue);
      expect(File(result.rightPageImagePath).existsSync(), isTrue);
      final left = img.decodeImage(
        File(result.leftPageImagePath).readAsBytesSync(),
      )!;
      final right = img.decodeImage(
        File(result.rightPageImagePath).readAsBytesSync(),
      )!;
      expect(left.width, closeTo(200, 15));
      expect(right.width, closeTo(200, 15));
    });

    test('reports low confidence when there is no visible gutter', () async {
      final image = img.Image(width: 400, height: 300);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));
      final path = writeImage(image, 'blank.jpg');

      final result = await provider.splitSpread(path);

      expect(result.confidence, lessThan(0.3));
    });

    test(
      'an explicit gutterXOverride splits at that position with full confidence',
      () async {
        final image = img.Image(width: 400, height: 300);
        img.fill(image, color: img.ColorRgb8(255, 255, 255));
        final path = writeImage(image, 'override.jpg');

        final result = await provider.splitSpread(path, gutterXOverride: 0.3);

        expect(result.confidence, 1.0);
        final left = img.decodeImage(
          File(result.leftPageImagePath).readAsBytesSync(),
        )!;
        expect(left.width, closeTo(120, 5));
      },
    );
  });

  group('dewarp', () {
    img.Image flatPageImage() {
      final image = img.Image(width: 300, height: 400);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));
      img.fillRect(
        image,
        x1: 0,
        y1: 50,
        x2: 299,
        y2: 349,
        color: img.ColorRgb8(200, 200, 200),
      );
      return image;
    }

    const bounds = Quad(
      topLeft: Point2D(x: 0, y: 0.1),
      topRight: Point2D(x: 1, y: 0.1),
      bottomRight: Point2D(x: 1, y: 0.95),
      bottomLeft: Point2D(x: 0, y: 0.95),
    );

    test('a flat page is left unchanged (no curvature to correct)', () async {
      final path = writeImage(flatPageImage(), 'flat.jpg');
      final originalBytes = File(path).readAsBytesSync();

      final result = await provider.dewarp(path, bounds);

      expect(result.occlusionDetected, isFalse);
      final outputBytes = File(result.flattenedImagePath).readAsBytesSync();
      expect(outputBytes.length, originalBytes.length);
    });

    test(
      'a page with real edge curvature is flattened into a new image',
      () async {
        final image = img.Image(width: 300, height: 400);
        img.fill(image, color: img.ColorRgb8(255, 255, 255));
        for (var x = 0; x < 300; x++) {
          final top = 50 + (0.001 * math.pow(x - 150, 2)).round();
          final bottom = 350 - (0.001 * math.pow(x - 150, 2)).round();
          for (var y = top; y <= bottom; y++) {
            image.setPixel(x, y, img.ColorRgb8(200, 200, 200));
          }
        }
        final path = writeImage(image, 'curved.jpg');

        final result = await provider.dewarp(path, bounds);

        expect(File(result.flattenedImagePath).existsSync(), isTrue);
        expect(
          result.flattenedImagePath.contains(
            '${p.separator}processed${p.separator}',
          ),
          isTrue,
          reason: 'dewarped artifact must persist outside tmpDir',
        );
        final flattened = img.decodeImage(
          File(result.flattenedImagePath).readAsBytesSync(),
        )!;
        // Flattening resamples the curved page region into a straight
        // rectangle at the bounds' pixel dimensions.
        expect(flattened.width, 300);
        expect(flattened.height, closeTo(400 * 0.85, 5));
      },
    );

    test(
      'a skin-toned patch over the core page region is flagged as high-confidence text loss',
      () async {
        final image = flatPageImage();
        img.fillRect(
          image,
          x1: 120,
          y1: 180,
          x2: 180,
          y2: 240,
          color: img.ColorRgb8(222, 170, 140),
        );
        final path = writeImage(image, 'finger_core.jpg');

        final result = await provider.dewarp(path, bounds);

        expect(result.occlusionDetected, isTrue);
        expect(result.occlusionHighConfidenceTextLoss, isTrue);
      },
    );

    test(
      'a skin-toned patch only in the outer margin is flagged but not as high-confidence text loss',
      () async {
        final image = flatPageImage();
        img.fillRect(
          image,
          x1: 0,
          y1: 50,
          x2: 20,
          y2: 349,
          color: img.ColorRgb8(222, 170, 140),
        );
        final path = writeImage(image, 'finger_margin.jpg');

        final result = await provider.dewarp(path, bounds);

        expect(result.occlusionDetected, isTrue);
        expect(result.occlusionHighConfidenceTextLoss, isFalse);
      },
    );
  });
}
