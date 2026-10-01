import 'dart:io';

import 'package:bookscanner/domain/models/capture_models.dart';
import 'package:bookscanner/domain/models/geometry.dart';
import 'package:bookscanner/domain/models/provider_info.dart';
import 'package:bookscanner/domain/models/scan_page.dart';
import 'package:bookscanner/domain/providers/image_enhancement_provider.dart';
import 'package:bookscanner/domain/providers/page_detection_provider.dart';
import 'package:bookscanner/domain/repositories/page_path_allocator.dart';
import 'package:bookscanner/domain/repositories/page_repository.dart';
import 'package:bookscanner/domain/use_cases/capture_page_use_case.dart';
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

class _FakeDetectionProvider implements PageDetectionProvider {
  @override
  ProviderInfo get info =>
      const ProviderInfo(providerName: 'fake', adapterVersion: '1');

  @override
  Future<Quad?> detectQuad(String imagePath) async => null;
}

class _ThrowingDetectionProvider implements PageDetectionProvider {
  @override
  ProviderInfo get info =>
      const ProviderInfo(providerName: 'fake-throwing', adapterVersion: '1');

  @override
  Future<Quad?> detectQuad(String imagePath) => throw const ProviderException(
    ProviderErrorCategory.modelUnavailable,
    'Detection model failed to load',
  );
}

class _FakeEnhancementProvider implements ImageEnhancementProvider {
  EnhancementRequest? lastRequest;
  Quad? cropWhenDetecting;

  @override
  ProviderInfo get info =>
      const ProviderInfo(providerName: 'fake', adapterVersion: '1');

  @override
  Future<double> scoreQuality(String imagePath) async => 0.9;

  @override
  Future<EnhancementResult> enhance(EnhancementRequest request) async {
    lastRequest = request;
    return EnhancementResult(
      processedImagePath: request.outputImagePath,
      thumbnailPath: request.outputImagePath,
      qualityScore: 0.9,
      providerInfo: info,
      cropPoints: request.detectCrop
          ? (cropWhenDetecting ?? request.cropPoints)
          : request.cropPoints,
    );
  }
}

void main() {
  late Directory tmpDir;
  late _FakePageRepository pageRepository;
  late _FakeEnhancementProvider enhancementProvider;
  late CapturePageUseCase useCase;
  late String originalImagePath;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp(
      'capture_page_use_case_test_',
    );
    final image = img.Image(width: 200, height: 300);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    originalImagePath = p.join(tmpDir.path, 'new_capture.jpg');
    await File(originalImagePath).writeAsBytes(img.encodeJpg(image));

    pageRepository = _FakePageRepository();
    enhancementProvider = _FakeEnhancementProvider();
    useCase = CapturePageUseCase(
      pageRepository: pageRepository,
      enhancementProvider: enhancementProvider,
      detectionProvider: _FakeDetectionProvider(),
      fileStorage: _PathsIn(tmpDir),
    );

    await pageRepository.addPage(
      ScanPage(
        id: 'p1',
        projectId: 'proj1',
        sequence: 2,
        logicalPageLabel: 'iv',
        originalImagePath: p.join(tmpDir.path, 'old_capture.jpg'),
        status: PageStatus.ready,
        filter: PageFilter.grayscale,
        brightness: 12,
        duplicateOfPageId: 'p0',
        likelyMissingBefore: true,
        dismissedWarnings: {'duplicate'},
      ),
    );
  });

  tearDown(() async {
    if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
  });

  test(
    'replacePage overwrites image content but preserves identity and filter settings',
    () async {
      final replaced = await useCase.replacePage(
        'p1',
        StillCapture(
          originalImagePath: originalImagePath,
          detectedQuad: null,
          qualityScore: 0.9,
          warnings: const {},
          capturedAtMs: 123,
          providerInfo: const ProviderInfo(
            providerName: 'fake-capture',
            adapterVersion: '1',
          ),
        ),
      );

      expect(replaced.id, 'p1');
      expect(replaced.projectId, 'proj1');
      expect(replaced.sequence, 2);
      expect(replaced.logicalPageLabel, 'iv');
      expect(replaced.originalImagePath, originalImagePath);
      expect(replaced.filter, PageFilter.grayscale);
      expect(replaced.brightness, 12);

      final persisted = await pageRepository.getPage('p1');
      expect(persisted?.originalImagePath, originalImagePath);
    },
  );

  test(
    'replacePage clears stale duplicate/missing-page anomaly flags',
    () async {
      final replaced = await useCase.replacePage(
        'p1',
        StillCapture(
          originalImagePath: originalImagePath,
          detectedQuad: null,
          qualityScore: 0.9,
          warnings: const {},
          capturedAtMs: 123,
          providerInfo: const ProviderInfo(
            providerName: 'fake-capture',
            adapterVersion: '1',
          ),
        ),
      );

      expect(replaced.duplicateOfPageId, isNull);
      expect(replaced.likelyMissingBefore, isFalse);
      expect(replaced.dismissedWarnings, isEmpty);
    },
  );

  test('replacePage throws for an unknown pageId', () async {
    expect(
      () => useCase.replacePage(
        'does-not-exist',
        StillCapture(
          originalImagePath: originalImagePath,
          detectedQuad: null,
          qualityScore: 0.9,
          warnings: const {},
          capturedAtMs: 123,
          providerInfo: const ProviderInfo(
            providerName: 'fake-capture',
            adapterVersion: '1',
          ),
        ),
      ),
      throwsStateError,
    );
  });

  test(
    'processCapture uses the crop returned by enhance(detectCrop: true)',
    () async {
      const detected = Quad(
        topLeft: Point2D(x: 0.1, y: 0.1),
        topRight: Point2D(x: 0.9, y: 0.12),
        bottomRight: Point2D(x: 0.92, y: 0.9),
        bottomLeft: Point2D(x: 0.08, y: 0.88),
      );
      enhancementProvider.cropWhenDetecting = detected;

      final page = await useCase.processCapture(
        capture: StillCapture(
          originalImagePath: originalImagePath,
          detectedQuad: Quad.fullFrame,
          qualityScore: 0.9,
          warnings: const {},
          capturedAtMs: 123,
          providerInfo: const ProviderInfo(
            providerName: 'fake-capture',
            adapterVersion: '1',
          ),
        ),
        projectId: 'proj1',
        sequence: 0,
      );

      expect(enhancementProvider.lastRequest?.detectCrop, isTrue);
      expect(page.cropPoints, detected);
      expect(page.originalImagePath, originalImagePath);
      expect(page.processedImagePath, isNot(originalImagePath));
      expect(page.filter, kDefaultCaptureFilter);
      expect(enhancementProvider.lastRequest?.filter, kDefaultCaptureFilter);
    },
  );

  test(
    'processCapture skips detect/crop for nativeReady scanner output',
    () async {
      await useCase.processCapture(
        capture: StillCapture(
          originalImagePath: originalImagePath,
          detectedQuad: Quad.fullFrame,
          qualityScore: 0.9,
          warnings: const {},
          capturedAtMs: 123,
          providerInfo: const ProviderInfo(
            providerName: 'cunning-document-scanner',
            adapterVersion: '1',
          ),
          nativeReady: true,
        ),
        projectId: 'proj1',
        sequence: 0,
      );

      expect(enhancementProvider.lastRequest?.passthrough, isTrue);
      expect(enhancementProvider.lastRequest?.detectCrop, isFalse);
    },
  );

  test(
    'processCapture keepOriginal stores the import without crop or document filter',
    () async {
      final page = await useCase.processCapture(
        capture: StillCapture(
          originalImagePath: originalImagePath,
          detectedQuad: null,
          qualityScore: 0.8,
          warnings: const {},
          capturedAtMs: 123,
          providerInfo: const ProviderInfo(
            providerName: 'pdf-import',
            adapterVersion: '1',
          ),
        ),
        projectId: 'proj1',
        sequence: 0,
        keepOriginal: true,
      );

      expect(enhancementProvider.lastRequest?.passthrough, isTrue);
      expect(enhancementProvider.lastRequest?.detectCrop, isFalse);
      expect(enhancementProvider.lastRequest?.filter, PageFilter.original);
      expect(page.filter, PageFilter.original);
    },
  );

  test(
    'reprocessPage with a new filter keeps the saved crop on the retained original',
    () async {
      const crop = Quad(
        topLeft: Point2D(x: 0.2, y: 0.15),
        topRight: Point2D(x: 0.85, y: 0.18),
        bottomRight: Point2D(x: 0.88, y: 0.9),
        bottomLeft: Point2D(x: 0.15, y: 0.88),
      );
      final rawPath = p.join(tmpDir.path, 'raw-camera.jpg');
      await File(originalImagePath).copy(rawPath);
      await pageRepository.addPage(
        ScanPage(
          id: 'p-crop',
          projectId: 'proj1',
          sequence: 0,
          originalImagePath: rawPath,
          processedImagePath: p.join(tmpDir.path, 'old.jpg'),
          cropPoints: crop,
          filter: PageFilter.blackAndWhite,
          status: PageStatus.ready,
        ),
      );
      final page = (await pageRepository.getPage('p-crop'))!;

      final updated = await useCase.reprocessPage(
        page,
        filter: PageFilter.photo,
      );

      expect(enhancementProvider.lastRequest?.cropPoints, crop);
      expect(enhancementProvider.lastRequest?.filter, PageFilter.photo);
      expect(enhancementProvider.lastRequest?.sourceImagePath, rawPath);
      expect(updated.cropPoints, crop);
      expect(updated.filter, PageFilter.photo);
      expect(updated.originalImagePath, rawPath);
      expect(File(rawPath).existsSync(), isTrue);
      expect(updated.hasDistinctOriginal, isTrue);
    },
  );

  group('detection-provider failure fallback (SPEC 9.7)', () {
    late CapturePageUseCase throwingUseCase;

    setUp(() {
      throwingUseCase = CapturePageUseCase(
        pageRepository: pageRepository,
        enhancementProvider: enhancementProvider,
        detectionProvider: _ThrowingDetectionProvider(),
        fileStorage: _PathsIn(tmpDir),
      );
    });

    test(
      'processCapture still saves the page when the detection provider throws, '
      'because crop finding now runs inside enhance rather than a separate call',
      () async {
        final page = await throwingUseCase.processCapture(
          capture: StillCapture(
            originalImagePath: originalImagePath,
            detectedQuad: null,
            qualityScore: 0.9,
            warnings: const {},
            capturedAtMs: 123,
            providerInfo: const ProviderInfo(
              providerName: 'fake-capture',
              adapterVersion: '1',
            ),
          ),
          projectId: 'proj1',
          sequence: 0,
        );

        expect(page.cropPoints, Quad.fullFrame);
        final persisted = await pageRepository.getPage(page.id);
        expect(persisted, isNotNull);
        expect(persisted?.originalImagePath, originalImagePath);
      },
    );

    test('replacePage still persists the new image when the detection provider '
        'would throw, instead of aborting the rescan', () async {
      final replaced = await throwingUseCase.replacePage(
        'p1',
        StillCapture(
          originalImagePath: originalImagePath,
          detectedQuad: null,
          qualityScore: 0.9,
          warnings: const {},
          capturedAtMs: 123,
          providerInfo: const ProviderInfo(
            providerName: 'fake-capture',
            adapterVersion: '1',
          ),
        ),
      );

      expect(replaced.cropPoints, Quad.fullFrame);
      expect(replaced.originalImagePath, originalImagePath);
    });
  });
}

class _PathsIn implements PagePathAllocator {
  _PathsIn(this._dir);
  final Directory _dir;

  @override
  String originalPathFor(String pageId, {required String ext}) =>
      p.join(_dir.path, '$pageId-original.$ext');

  @override
  String processedPathFor(String pageId, {required String ext}) =>
      p.join(_dir.path, '$pageId-processed.$ext');

  @override
  String thumbnailPathFor(String pageId) =>
      p.join(_dir.path, '$pageId-thumb.jpg');

  @override
  String exportPathFor(String jobId, String extension) =>
      p.join(_dir.path, '$jobId.$extension');
}
