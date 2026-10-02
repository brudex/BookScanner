import 'dart:io';

import 'package:bookscanner/domain/models/capture_models.dart';
import 'package:bookscanner/domain/models/geometry.dart';
import 'package:bookscanner/domain/models/project.dart';
import 'package:bookscanner/domain/models/provider_info.dart';
import 'package:bookscanner/domain/models/scan_page.dart';
import 'package:bookscanner/domain/providers/book_dewarp_provider.dart';
import 'package:bookscanner/domain/providers/image_enhancement_provider.dart';
import 'package:bookscanner/domain/providers/page_detection_provider.dart';
import 'package:bookscanner/domain/repositories/page_path_allocator.dart';
import 'package:bookscanner/domain/repositories/page_repository.dart';
import 'package:bookscanner/domain/use_cases/process_book_spread_use_case.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

class _FakePageRepository implements PageRepository {
  final pages = <String, ScanPage>{};

  @override
  Future<ScanPage?> getPage(String pageId) async => pages[pageId];

  @override
  Future<void> addPage(ScanPage page) async => pages[page.id] = page;

  @override
  Future<void> updatePage(ScanPage page) async => pages[page.id] = page;

  @override
  Future<List<ScanPage>> getPages(String projectId) async =>
      pages.values.where((p) => p.projectId == projectId).toList();

  @override
  Future<void> deletePage(String pageId) async => pages.remove(pageId);

  @override
  Future<void> duplicatePage(String pageId) async {}

  @override
  Future<void> reorderPages(String projectId, List<String> order) async {}

  @override
  Stream<List<ScanPage>> watchPages(String projectId) => const Stream.empty();
}

/// Fake that mimics the real provider's contract shape (two distinct output
/// files, confidence signal) without doing real image analysis, so use-case
/// orchestration can be tested independently of the classical CV heuristics
/// (which have their own dedicated tests in
/// `dart_book_dewarp_provider_test.dart`).
class _FakeBookDewarpProvider implements BookDewarpProvider {
  _FakeBookDewarpProvider(this._tmpDir);

  final Directory _tmpDir;
  int splitCalls = 0;
  int dewarpCalls = 0;
  double? lastGutterOverride;
  Quad? lastBounds;
  String? lastOutputPath;
  bool occlusionOnNextDewarp = false;
  bool highConfidenceTextLossOnNextDewarp = false;

  @override
  ProviderInfo get info =>
      const ProviderInfo(providerName: 'fake-book-dewarp', adapterVersion: '1');

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<SpreadSplitResult> splitSpread(
    String spreadImagePath, {
    double? gutterXOverride,
  }) async {
    splitCalls++;
    lastGutterOverride = gutterXOverride;
    final image = img.Image(width: 100, height: 200);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    final leftPath = p.join(_tmpDir.path, 'split_left_$splitCalls.jpg');
    final rightPath = p.join(_tmpDir.path, 'split_right_$splitCalls.jpg');
    File(leftPath).writeAsBytesSync(img.encodeJpg(image));
    File(rightPath).writeAsBytesSync(img.encodeJpg(image));
    return SpreadSplitResult(
      leftPageImagePath: leftPath,
      rightPageImagePath: rightPath,
      confidence: gutterXOverride != null ? 1.0 : 0.8,
      providerInfo: info,
    );
  }

  @override
  Future<DewarpResult> dewarp(
    String pageImagePath,
    Quad pageBounds, {
    String? outputPath,
  }) async {
    dewarpCalls++;
    lastBounds = pageBounds;
    lastOutputPath = outputPath;
    final path = outputPath ?? pageImagePath;
    if (outputPath != null && outputPath != pageImagePath) {
      File(pageImagePath).copySync(outputPath);
    }
    return DewarpResult(
      flattenedImagePath: path,
      providerInfo: info,
      occlusionDetected: occlusionOnNextDewarp,
      occlusionHighConfidenceTextLoss: highConfidenceTextLossOnNextDewarp,
    );
  }
}

class _FakeDetectionProvider implements PageDetectionProvider {
  @override
  ProviderInfo get info =>
      const ProviderInfo(providerName: 'fake-detection', adapterVersion: '1');

  @override
  Future<Quad?> detectQuad(String imagePath) async => null;
}

class _FakeEnhancementProvider implements ImageEnhancementProvider {
  double nextQualityScore = 0.9;
  EnhancementRequest? lastRequest;

  @override
  ProviderInfo get info =>
      const ProviderInfo(providerName: 'fake-enhancement', adapterVersion: '1');

  @override
  Future<double> scoreQuality(String imagePath) async => nextQualityScore;

  @override
  Future<EnhancementResult> enhance(EnhancementRequest request) async {
    lastRequest = request;
    File(request.sourceImagePath).copySync(request.outputImagePath);
    return EnhancementResult(
      processedImagePath: request.outputImagePath,
      thumbnailPath: '${request.outputImagePath}.thumb.jpg',
      qualityScore: nextQualityScore,
      providerInfo: info,
    );
  }
}

class _FakePaths implements PagePathAllocator {
  _FakePaths(this._tmpDir);
  final Directory _tmpDir;

  @override
  String originalPathFor(String pageId, {required String ext}) =>
      p.join(_tmpDir.path, '$pageId-original.$ext');

  @override
  String processedPathFor(String pageId, {required String ext}) =>
      p.join(_tmpDir.path, '$pageId-processed.$ext');

  @override
  String thumbnailPathFor(String pageId) =>
      p.join(_tmpDir.path, '$pageId-thumb.jpg');

  @override
  String exportPathFor(String jobId, String extension) =>
      p.join(_tmpDir.path, '$jobId.$extension');
}

void main() {
  late Directory tmpDir;
  late _FakePageRepository pageRepository;
  late _FakeBookDewarpProvider dewarpProvider;
  late _FakeDetectionProvider detectionProvider;
  late _FakeEnhancementProvider enhancementProvider;
  late ProcessBookSpreadUseCase useCase;
  late String spreadImagePath;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp(
      'book_spread_use_case_test_',
    );
    final image = img.Image(width: 400, height: 300);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    spreadImagePath = p.join(tmpDir.path, 'spread.jpg');
    File(spreadImagePath).writeAsBytesSync(img.encodeJpg(image));

    pageRepository = _FakePageRepository();
    dewarpProvider = _FakeBookDewarpProvider(tmpDir);
    detectionProvider = _FakeDetectionProvider();
    enhancementProvider = _FakeEnhancementProvider();
    useCase = ProcessBookSpreadUseCase(
      pageRepository: pageRepository,
      dewarpProvider: dewarpProvider,
      detectionProvider: detectionProvider,
      enhancementProvider: enhancementProvider,
      fileStorage: _FakePaths(tmpDir),
    );
  });

  tearDown(() async {
    if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
  });

  StillCapture buildCapture() => StillCapture(
    originalImagePath: spreadImagePath,
    detectedQuad: null,
    qualityScore: 0.9,
    warnings: const {},
    capturedAtMs: 12345,
    providerInfo: const ProviderInfo(
      providerName: 'fake-capture',
      adapterVersion: '1',
    ),
  );

  test(
    'produces two persisted, cross-linked pages in left-to-right order',
    () async {
      final pages = await useCase.processCapture(
        capture: buildCapture(),
        projectId: 'proj1',
        sequence: 4,
      );

      expect(pages, hasLength(2));
      expect(pages[0].sequence, 4);
      expect(pages[1].sequence, 5);
      expect(pages[0].spreadSiblingPageId, pages[1].id);
      expect(pages[1].spreadSiblingPageId, pages[0].id);
      expect(pageRepository.pages, hasLength(2));
      expect(pageRepository.pages[pages[0].id], isNotNull);
      expect(pageRepository.pages[pages[1].id], isNotNull);
    },
  );

  test('reverses sequence assignment for right-to-left books', () async {
    final pages = await useCase.processCapture(
      capture: buildCapture(),
      projectId: 'proj1',
      sequence: 0,
      pageOrderDirection: PageOrderDirection.rightToLeft,
    );

    // The physically-right half of the spread reads first in an RTL book.
    expect(pages[0].sequence, 0);
    expect(pages[1].sequence, 1);
  });

  test('records only the center split — no detect, filter, or dewarp', () async {
    final pages = await useCase.processCapture(
      capture: buildCapture(),
      projectId: 'proj1',
      sequence: 0,
    );

    expect(dewarpProvider.lastGutterOverride, 0.5);
    expect(dewarpProvider.dewarpCalls, 0);
    for (final page in pages) {
      expect(page.stages[PipelineStage.split], isNotNull);
      expect(page.stages[PipelineStage.detection], isNull);
      expect(page.stages[PipelineStage.enhancement], isNull);
      expect(page.stages[PipelineStage.dewarp], isNull);
      expect(page.cropPoints, Quad.fullFrame);
      expect(page.filter, PageFilter.original);
    }
  });

  test('book capture does not run finger detection or mark a rescan', () async {
    dewarpProvider.occlusionOnNextDewarp = true;
    dewarpProvider.highConfidenceTextLossOnNextDewarp = true;

    final pages = await useCase.processCapture(
      capture: buildCapture(),
      projectId: 'proj1',
      sequence: 0,
    );

    expect(dewarpProvider.dewarpCalls, 0);
    for (final page in pages) {
      expect(page.warnings, isEmpty);
      expect(page.status, PageStatus.ready);
    }
  });

  test(
    'book capture stays ready even if a later dewarp would have flagged an occlusion',
    () async {
      dewarpProvider.occlusionOnNextDewarp = true;
      dewarpProvider.highConfidenceTextLossOnNextDewarp = false;

      final pages = await useCase.processCapture(
        capture: buildCapture(),
        projectId: 'proj1',
        sequence: 0,
      );

      expect(dewarpProvider.dewarpCalls, 0);
      for (final page in pages) {
        expect(page.status, PageStatus.ready);
      }
    },
  );

  test(
    'resplit re-runs the pipeline at an explicit gutter position, preserving ids and sequence',
    () async {
      final original = await useCase.processCapture(
        capture: buildCapture(),
        projectId: 'proj1',
        sequence: 2,
      );
      final leftPage = original[0];
      final rightPage = original[1];

      final resplit = await useCase.resplit(
        leftPage: leftPage,
        rightPage: rightPage,
        originalSpreadImagePath: spreadImagePath,
        gutterX: 0.4,
      );

      expect(dewarpProvider.lastGutterOverride, 0.4);
      expect(resplit[0].id, leftPage.id);
      expect(resplit[1].id, rightPage.id);
      expect(resplit[0].sequence, leftPage.sequence);
      expect(resplit[1].sequence, rightPage.sequence);
      expect(pageRepository.pages[leftPage.id], isNotNull);
      expect(pageRepository.pages[rightPage.id], isNotNull);
    },
  );

  test(
    'processCapture retains the undivided spread photo, findable via spreadOriginalPathFor for either sibling id',
    () async {
      final pages = await useCase.processCapture(
        capture: buildCapture(),
        projectId: 'proj1',
        sequence: 0,
      );
      final paths = _FakePaths(tmpDir);

      final pathViaLeft = ProcessBookSpreadUseCase.spreadOriginalPathFor(
        paths,
        pages[0].id,
        pages[1].id,
      );
      final pathViaRight = ProcessBookSpreadUseCase.spreadOriginalPathFor(
        paths,
        pages[1].id,
        pages[0].id,
      );

      expect(pathViaLeft, pathViaRight);
      expect(File(pathViaLeft).existsSync(), isTrue);

      // The retained photo is a genuine, independent copy of the capture --
      // re-splitting from it must succeed just like the direct-path test
      // above.
      final resplit = await useCase.resplit(
        leftPage: pages[0],
        rightPage: pages[1],
        originalSpreadImagePath: pathViaLeft,
        gutterX: 0.6,
      );
      expect(resplit, hasLength(2));
    },
  );

  test('already-split halves skip crop re-detect (full-frame page image)', () async {
    await useCase.processCapture(
      capture: buildCapture(),
      projectId: 'proj1',
      sequence: 0,
    );

    expect(enhancementProvider.lastRequest, isNull);
    expect(dewarpProvider.dewarpCalls, 0);
    expect(pageRepository.pages.values.first.cropPoints, Quad.fullFrame);
    expect(pageRepository.pages.values.first.filter, PageFilter.original);
  });

  test(
    'processSinglePage stores the photo as processing without enhancing yet',
    () async {
      final pages = await useCase.processSinglePage(
        capture: buildCapture(),
        projectId: 'proj1',
        sequence: 0,
      );

      expect(enhancementProvider.lastRequest, isNull);
      expect(pages.single.status, PageStatus.processing);
      expect(pages.single.cropPoints, Quad.fullFrame);
      expect(pages.single.filter, PageFilter.original);
      expect(pages.single.processedImagePath, pages.single.originalImagePath);
    },
  );

  test(
    'processSinglePage persists the full photo without dewarp or a sibling',
    () async {
      final pages = await useCase.processSinglePage(
        capture: buildCapture(),
        projectId: 'proj1',
        sequence: 3,
      );

      expect(pages, hasLength(1));
      expect(pages.single.sequence, 3);
      expect(pages.single.status, PageStatus.processing);
      expect(pages.single.spreadSiblingPageId, isNull);
      expect(pages.single.stages[PipelineStage.split], isNull);
      expect(pages.single.stages[PipelineStage.dewarp], isNull);
      expect(pages.single.cropPoints, Quad.fullFrame);
      expect(dewarpProvider.splitCalls, 0);
      expect(dewarpProvider.dewarpCalls, 0);
      expect(pageRepository.pages, hasLength(1));
    },
  );

  test('enhanceSavedPage crops and applies the default document filter', () async {
    final pages = await useCase.processSinglePage(
      capture: buildCapture(),
      projectId: 'proj1',
      sequence: 0,
    );
    final enhanced = await useCase.enhanceSavedPage(pages.single);

    expect(enhancementProvider.lastRequest, isNotNull);
    expect(enhancementProvider.lastRequest!.detectCrop, isTrue);
    expect(enhancementProvider.lastRequest!.filter, PageFilter.enhancedColor);
    expect(enhancementProvider.lastRequest!.splitOpenBook, isFalse);
    expect(enhanced.status, PageStatus.ready);
    expect(enhanced.filter, PageFilter.enhancedColor);
    expect(enhanced.stages[PipelineStage.enhancement], isNotNull);
    expect(enhanced.processedImagePath, isNot(pages.single.originalImagePath));
  });
}
