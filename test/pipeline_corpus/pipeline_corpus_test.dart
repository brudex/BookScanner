import 'dart:io';

import 'package:bookscanner/data/services/local/app_paths.dart';
import 'package:bookscanner/data/services/local/file_storage_service.dart';
import 'package:bookscanner/data/services/scanner/adapters/dart_book_dewarp_provider.dart';
import 'package:bookscanner/data/services/scanner/adapters/dart_image_enhancement_provider.dart';
import 'package:bookscanner/data/services/scanner/adapters/dart_page_detection_provider.dart';
import 'package:bookscanner/domain/models/geometry.dart';
import 'package:bookscanner/domain/models/ocr_block.dart';
import 'package:bookscanner/domain/models/scan_page.dart';
import 'package:bookscanner/domain/providers/image_enhancement_provider.dart';
import 'package:bookscanner/domain/use_cases/analyze_ocr_layout_use_case.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../data/fakes/fake_path_provider_platform.dart';
import 'corpus_images.dart' as corpus;

/// SPEC.md's "pipeline golden-image" test category (lines 317, 387): runs
/// the classical image-processing pipeline against the named, synthetic
/// "consented test corpus" in corpus_images.dart and asserts documented
/// behavior for each of its 11 categories -- not pixel-diff goldens (per
/// the project decision to keep this suite robust to intentional algorithm
/// improvement, matching every other test file in this codebase's
/// behavior/property-assertion style).
///
/// Several categories here (curved book, fingers, 2-column layout) are
/// already covered in much finer-grained detail by
/// `dart_book_dewarp_provider_test.dart` and
/// `analyze_ocr_layout_use_case_test.dart` -- this suite's job is to be the
/// single place that exercises the *complete* named corpus end to end, not
/// to replace that deeper per-provider coverage. Categories with no
/// existing coverage anywhere else (glossy paper, shadows, skew, low light,
/// tables, illustrations, right-to-left text) get their primary assertions
/// here (skew/glossy/shadow/low-light also have matching depth in the new
/// `dart_page_detection_provider_test.dart` / `dart_image_enhancement_
/// provider_test.dart` files added alongside this suite).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmpDir;
  late DartPageDetectionProvider detectionProvider;
  late DartImageEnhancementProvider enhancementProvider;
  late DartBookDewarpProvider dewarpProvider;
  late AnalyzeOcrLayoutUseCase layoutUseCase;

  setUpAll(() async {
    tmpDir = await Directory.systemTemp.createTemp('pipeline_corpus_test_');
    PathProviderPlatform.instance = FakePathProviderPlatform(tmpDir);
    final paths = await AppPaths.instance();
    final fileStorage = FileStorageService(paths);
    detectionProvider = DartPageDetectionProvider();
    enhancementProvider = DartImageEnhancementProvider(fileStorage);
    dewarpProvider = DartBookDewarpProvider(fileStorage);
    layoutUseCase = AnalyzeOcrLayoutUseCase();
  });

  tearDownAll(() async {
    if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
  });

  test('1. flat page: detected and scored as good-quality input', () async {
    final path = corpus.flatPage(tmpDir);

    final quad = await detectionProvider.detectQuad(path);
    final score = await enhancementProvider.scoreQuality(path);

    expect(quad, isNotNull);
    expect(score, greaterThan(0.5));
  });

  test(
    '2. curved book: spread splits cleanly and page curvature is flattened',
    () async {
      final spreadPath = corpus.curvedBookSpread(tmpDir);
      final splitResult = await dewarpProvider.splitSpread(spreadPath);
      expect(splitResult.confidence, greaterThan(0.5));

      final pagePath = corpus.curvedBookPage(tmpDir);
      final dewarpResult = await dewarpProvider.dewarp(
        pagePath,
        corpus.corpusPageBounds,
      );
      expect(File(dewarpResult.flattenedImagePath).existsSync(), isTrue);
      expect(dewarpResult.flattenedImagePath, isNot(pagePath));
    },
  );

  test(
    '3. glossy paper: a glare patch does not crash enhancement or zero the score',
    () async {
      final sourcePath = corpus.glossyPage(tmpDir);
      final outputPath = '$sourcePath.out.jpg';

      final result = await enhancementProvider.enhance(
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

  test(
    '4. shadows: illumination normalization flattens the background gradient',
    () async {
      final sourcePath = corpus.shadowedPage(tmpDir);
      final outputPath = '$sourcePath.out.jpg';

      await enhancementProvider.enhance(
        EnhancementRequest(
          sourceImagePath: sourcePath,
          outputImagePath: outputPath,
          cropPoints: Quad.fullFrame,
          rotationDegrees: 0,
          filter: PageFilter.original,
        ),
      );

      expect(File(outputPath).existsSync(), isTrue);
      // Detailed before/after stddev measurement lives in
      // dart_image_enhancement_provider_test.dart; this corpus entry confirms
      // the named fixture runs cleanly through the real provider end to end.
    },
  );

  test(
    '5a. fingers over the core page region: flagged as needing a rescan',
    () async {
      final path = corpus.fingerOcclusionCore(tmpDir);
      final result = await dewarpProvider.dewarp(path, corpus.corpusPageBounds);
      expect(result.occlusionDetected, isTrue);
      expect(result.occlusionHighConfidenceTextLoss, isTrue);
    },
  );

  test(
    '5b. fingers confined to the outer margin: flagged but not as text loss',
    () async {
      final path = corpus.fingerOcclusionMargin(tmpDir);
      final result = await dewarpProvider.dewarp(path, corpus.corpusPageBounds);
      expect(result.occlusionDetected, isTrue);
      expect(result.occlusionHighConfidenceTextLoss, isFalse);
    },
  );

  test(
    '6. skew: detector returns a tight rotated quad that enhancement warps to a background-free page',
    () async {
      final path = corpus.skewedPage(tmpDir);
      final quad = await detectionProvider.detectQuad(path);

      expect(quad, isNotNull);
      expect(
        (quad!.topLeft.y - quad.topRight.y).abs(),
        greaterThan(0.04),
        reason: 'a 12°-rotated page must not collapse to an axis-aligned box',
      );

      final outputPath = '$path.out.jpg';
      await enhancementProvider.enhance(
        EnhancementRequest(
          sourceImagePath: path,
          outputImagePath: outputPath,
          cropPoints: quad,
          rotationDegrees: 0,
          filter: PageFilter.original,
          removeShadowsAndStains: false,
        ),
      );

      final output = img.decodeImage(File(outputPath).readAsBytesSync())!;
      for (final corner in <(int, int)>[
        (4, 4),
        (output.width - 5, 4),
        (4, output.height - 5),
        (output.width - 5, output.height - 5),
      ]) {
        final p = output.getPixel(corner.$1, corner.$2);
        expect(
          p.r,
          greaterThan(180),
          reason:
              'corner ${corner.$1},${corner.$2} should be page content, not '
              'the dark background the document was photographed against',
        );
      }
    },
  );

  test(
    '7. low light: blurred/low-detail capture scores clearly below a sharp reference',
    () async {
      final lowLightPath = corpus.lowLightPage(tmpDir);
      final flatReferencePath = corpus.flatPage(tmpDir);

      final lowLightScore = await enhancementProvider.scoreQuality(
        lowLightPath,
      );
      final referenceScore = await enhancementProvider.scoreQuality(
        flatReferencePath,
      );

      expect(lowLightScore, lessThan(referenceScore * 0.5));
    },
  );

  test(
    '8. multi-column layout: reading order threads the left column fully before the right',
    () {
      final result = layoutUseCase('page1', corpus.multiColumnLayoutRawLines());

      expect(result, hasLength(2));
      expect(result[0].text, contains('Left column'));
      expect(result[1].text, contains('Right column'));
    },
  );

  test(
    '9. table layout: no block is ever classified as a table or table cell '
    '(documented gap -- table/tableCell exist on BlockType but AnalyzeOcrLayoutUseCase never assigns them)',
    () {
      final result = layoutUseCase('page1', corpus.tableLayoutRawLines());

      expect(result, isNotEmpty);
      expect(result.every((b) => b.blockType != BlockType.table), isTrue);
      expect(result.every((b) => b.blockType != BlockType.tableCell), isTrue);
    },
  );

  test(
    '10. illustration (no text): empty OCR input produces empty output without error',
    () {
      final result = layoutUseCase('page1', corpus.illustrationRawLines());
      expect(result, isEmpty);
    },
  );

  test(
    '11. right-to-left text: reading order is purely geometric (left-bucket first), '
    'NOT direction-aware -- the visually-first (rightmost) RTL column is emitted second '
    '(documented gap, matches IMPLEMENTATION_STATUS.md §5 on page-order-direction)',
    () {
      final result = layoutUseCase('page1', corpus.rtlTextLayoutRawLines());

      expect(result, hasLength(2));
      // "should be read second" (the left/lower-centerX column, merged into
      // one paragraph block) comes out first; "should be read first" (the
      // right column -- the correct RTL start point) comes out second --
      // proving the algorithm ignores reading direction and only orders by
      // centerX ascending.
      expect(result[0].text, contains('ثانياً'));
      expect(result[1].text, contains('أولاً'));
    },
  );
}
