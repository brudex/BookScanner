import 'dart:io';

import 'package:bookscanner/domain/models/geometry.dart';
import 'package:bookscanner/domain/models/provider_info.dart';
import 'package:bookscanner/domain/models/scan_page.dart';
import 'package:bookscanner/domain/providers/image_enhancement_provider.dart';
import 'package:bookscanner/domain/providers/page_detection_provider.dart';
import 'package:bookscanner/domain/repositories/page_path_allocator.dart';
import 'package:bookscanner/domain/repositories/page_repository.dart';
import 'package:bookscanner/domain/use_cases/capture_page_use_case.dart';
import 'package:bookscanner/ui/features/page_review/view_models/crop_correction_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

class _FakePageRepository implements PageRepository {
  final _pages = <String, ScanPage>{};

  @override
  Future<ScanPage?> getPage(String pageId) async => _pages[pageId];

  @override
  Future<void> updatePage(ScanPage page) async => _pages[page.id] = page;

  @override
  Future<void> addPage(ScanPage page) async => _pages[page.id] = page;

  @override
  Future<List<ScanPage>> getPages(String projectId) async =>
      _pages.values.where((p) => p.projectId == projectId).toList();

  @override
  Future<void> deletePage(String pageId) async => _pages.remove(pageId);

  @override
  Future<void> duplicatePage(String pageId) async {}

  @override
  Future<void> reorderPages(
    String projectId,
    List<String> newPageIdOrder,
  ) async {}

  @override
  Stream<List<ScanPage>> watchPages(String projectId) => const Stream.empty();
}

class _FakeDetectionProvider implements PageDetectionProvider {
  Quad? nextResult;

  @override
  ProviderInfo get info =>
      const ProviderInfo(providerName: 'fake', adapterVersion: '1');

  @override
  Future<Quad?> detectQuad(String imagePath) async => nextResult;
}

class _FakeEnhancementProvider implements ImageEnhancementProvider {
  EnhancementRequest? lastRequest;

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
    );
  }
}

class _FakePaths implements PagePathAllocator {
  @override
  String originalPathFor(String pageId, {required String ext}) =>
      '/tmp/$pageId-original.$ext';

  @override
  String processedPathFor(String pageId, {required String ext}) =>
      '/tmp/$pageId-processed.$ext';

  @override
  String thumbnailPathFor(String pageId) => '/tmp/$pageId-thumb.jpg';

  @override
  String exportPathFor(String jobId, String extension) =>
      '/tmp/$jobId.$extension';
}

void main() {
  late Directory tmpDir;
  late _FakePageRepository pageRepository;
  late _FakeDetectionProvider detectionProvider;
  late _FakeEnhancementProvider enhancementProvider;
  late CropCorrectionViewModel viewModel;
  late String imagePath;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('crop_vm_test_');
    final image = img.Image(width: 200, height: 100);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    imagePath = p.join(tmpDir.path, 'page.jpg');
    await File(imagePath).writeAsBytes(img.encodeJpg(image));

    pageRepository = _FakePageRepository();
    detectionProvider = _FakeDetectionProvider();
    enhancementProvider = _FakeEnhancementProvider();

    await pageRepository.addPage(
      ScanPage(
        id: 'p1',
        projectId: 'proj1',
        sequence: 0,
        originalImagePath: imagePath,
        status: PageStatus.ready,
      ),
    );

    viewModel = CropCorrectionViewModel(
      pageId: 'p1',
      pageRepository: pageRepository,
      capturePageUseCase: CapturePageUseCase(
        pageRepository: pageRepository,
        enhancementProvider: enhancementProvider,
        detectionProvider: detectionProvider,
        fileStorage: _FakePaths(),
      ),
      detectionProvider: detectionProvider,
    );
  });

  tearDown(() async {
    if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
  });

  test(
    'initialize loads the page, decodes intrinsic image size, defaults to full-frame quad',
    () async {
      await viewModel.initialize();

      expect(viewModel.loading, isFalse);
      expect(viewModel.page, isNotNull);
      expect(viewModel.imageSize?.width, 200);
      expect(viewModel.imageSize?.height, 100);
      expect(viewModel.quad, Quad.fullFrame);
    },
  );

  test('initialize uses the page\'s existing cropPoints when set', () async {
    const existingQuad = Quad(
      topLeft: Point2D(x: 0.1, y: 0.1),
      topRight: Point2D(x: 0.9, y: 0.1),
      bottomRight: Point2D(x: 0.9, y: 0.9),
      bottomLeft: Point2D(x: 0.1, y: 0.9),
    );
    final page = (await pageRepository.getPage('p1'))!;
    await pageRepository.updatePage(page.copyWith(cropPoints: existingQuad));

    await viewModel.initialize();

    expect(viewModel.quad, existingQuad);
  });

  test(
    'dragCorner moves only the targeted corner and clamps to 0..1',
    () async {
      await viewModel.initialize();

      viewModel.dragCorner(CropCorner.topLeft, const Offset(0.2, 0.3));
      expect(viewModel.quad.topLeft, const Point2D(x: 0.2, y: 0.3));
      expect(viewModel.quad.topRight, Quad.fullFrame.topRight);
      expect(viewModel.quad.bottomRight, Quad.fullFrame.bottomRight);
      expect(viewModel.quad.bottomLeft, Quad.fullFrame.bottomLeft);

      // Dragging past the edge clamps rather than overshoots.
      viewModel.dragCorner(CropCorner.topLeft, const Offset(-5, -5));
      expect(viewModel.quad.topLeft, const Point2D(x: 0.0, y: 0.0));
    },
  );

  test('resetToFullFrame restores Quad.fullFrame', () async {
    await viewModel.initialize();
    viewModel.dragCorner(CropCorner.topLeft, const Offset(0.3, 0.3));
    expect(viewModel.quad, isNot(Quad.fullFrame));

    viewModel.resetToFullFrame();
    expect(viewModel.quad, Quad.fullFrame);
  });

  test(
    'resetToDetected applies the detection provider\'s quad, or full-frame if null',
    () async {
      await viewModel.initialize();

      const detected = Quad(
        topLeft: Point2D(x: 0.05, y: 0.05),
        topRight: Point2D(x: 0.95, y: 0.05),
        bottomRight: Point2D(x: 0.95, y: 0.95),
        bottomLeft: Point2D(x: 0.05, y: 0.95),
      );
      detectionProvider.nextResult = detected;
      await viewModel.resetToDetected();
      expect(viewModel.quad, detected);

      detectionProvider.nextResult = null;
      await viewModel.resetToDetected();
      expect(viewModel.quad, Quad.fullFrame);
    },
  );

  test(
    'apply calls reprocessPage with the current quad and persists it on the page',
    () async {
      await viewModel.initialize();
      viewModel.dragCorner(CropCorner.bottomRight, const Offset(-0.1, -0.1));
      final appliedQuad = viewModel.quad;

      final ok = await viewModel.apply();

      expect(ok, isTrue);
      expect(enhancementProvider.lastRequest?.cropPoints, appliedQuad);
      final updated = await pageRepository.getPage('p1');
      expect(updated?.cropPoints, appliedQuad);
    },
  );
}
