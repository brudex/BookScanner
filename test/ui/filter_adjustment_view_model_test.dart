import 'dart:io';

import 'package:bookscanner/domain/models/geometry.dart';
import 'package:bookscanner/domain/models/provider_info.dart';
import 'package:bookscanner/domain/models/scan_page.dart';
import 'package:bookscanner/domain/providers/image_enhancement_provider.dart';
import 'package:bookscanner/domain/providers/page_detection_provider.dart';
import 'package:bookscanner/domain/repositories/page_path_allocator.dart';
import 'package:bookscanner/domain/repositories/page_repository.dart';
import 'package:bookscanner/domain/use_cases/capture_page_use_case.dart';
import 'package:bookscanner/ui/features/page_review/view_models/filter_adjustment_view_model.dart';
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
  @override
  ProviderInfo get info =>
      const ProviderInfo(providerName: 'fake', adapterVersion: '1');

  @override
  Future<Quad?> detectQuad(String imagePath) async => null;
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
  late _FakeEnhancementProvider enhancementProvider;
  late FilterAdjustmentViewModel viewModel;
  late String imagePath;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp(
      'filter_adjustment_vm_test_',
    );
    final image = img.Image(width: 200, height: 100);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    imagePath = p.join(tmpDir.path, 'page.jpg');
    await File(imagePath).writeAsBytes(img.encodeJpg(image));

    pageRepository = _FakePageRepository();
    enhancementProvider = _FakeEnhancementProvider();

    await pageRepository.addPage(
      ScanPage(
        id: 'p1',
        projectId: 'proj1',
        sequence: 0,
        originalImagePath: imagePath,
        processedImagePath: p.join(tmpDir.path, 'processed.jpg'),
        status: PageStatus.ready,
        filter: PageFilter.grayscale,
        brightness: 10,
        contrast: -5,
        sharpness: 20,
      ),
    );

    viewModel = FilterAdjustmentViewModel(
      pageId: 'p1',
      pageRepository: pageRepository,
      capturePageUseCase: CapturePageUseCase(
        pageRepository: pageRepository,
        enhancementProvider: enhancementProvider,
        detectionProvider: _FakeDetectionProvider(),
        fileStorage: _FakePaths(),
      ),
    );
  });

  tearDown(() async {
    if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
  });

  test(
    'initialize seeds filter/brightness/contrast/sharpness from the page',
    () async {
      await viewModel.initialize();

      expect(viewModel.loading, isFalse);
      expect(viewModel.filter, PageFilter.grayscale);
      expect(viewModel.brightness, 10);
      expect(viewModel.contrast, -5);
      expect(viewModel.sharpness, 20);
      expect(viewModel.showingSavedProcessed, isTrue);
      expect(viewModel.previewImagePath, endsWith('processed.jpg'));
    },
  );

  test(
    'changing a filter keeps the cropped processed framing, not the full original',
    () async {
      await viewModel.initialize();
      expect(viewModel.showingSavedProcessed, isTrue);

      viewModel.selectFilter(PageFilter.blackAndWhite);

      expect(viewModel.showingSavedProcessed, isFalse);
      // Until the live render finishes, fall back to last processed (cropped),
      // never the full-bleed camera original.
      expect(viewModel.previewImagePath, endsWith('processed.jpg'));
    },
  );

  test(
    'selectFilter/setBrightness/setContrast/setSharpness mutate local state only',
    () async {
      await viewModel.initialize();

      viewModel.selectFilter(PageFilter.blackAndWhite);
      viewModel.setBrightness(50);
      viewModel.setContrast(-30);
      viewModel.setSharpness(80);

      expect(viewModel.filter, PageFilter.blackAndWhite);
      expect(viewModel.brightness, 50);
      expect(viewModel.contrast, -30);
      expect(viewModel.sharpness, 80);
      // Not persisted until apply().
      final stillOriginal = await pageRepository.getPage('p1');
      expect(stillOriginal?.filter, PageFilter.grayscale);
    },
  );

  test(
    'apply calls reprocessPage with the current selections and persists them on the page',
    () async {
      await viewModel.initialize();
      viewModel.selectFilter(PageFilter.photo);
      viewModel.setBrightness(15);
      viewModel.setContrast(25);
      viewModel.setSharpness(40);

      final ok = await viewModel.apply();

      expect(ok, isTrue);
      expect(enhancementProvider.lastRequest?.filter, PageFilter.photo);
      expect(enhancementProvider.lastRequest?.brightness, 15);
      expect(enhancementProvider.lastRequest?.contrast, 25);
      expect(enhancementProvider.lastRequest?.sharpness, 40);

      final updated = await pageRepository.getPage('p1');
      expect(updated?.filter, PageFilter.photo);
      expect(updated?.brightness, 15);
      expect(updated?.contrast, 25);
      expect(updated?.sharpness, 40);
      expect(viewModel.page?.filter, PageFilter.photo);
      expect(viewModel.showingSavedProcessed, isTrue);
      expect(viewModel.previewEpoch, greaterThan(0));
    },
  );

  test(
    'reloadFromRepository adopts crop/filter changes written by another screen',
    () async {
      await viewModel.initialize();
      expect(viewModel.showingSavedProcessed, isTrue);

      final existing = (await pageRepository.getPage('p1'))!;
      await pageRepository.updatePage(
        existing.copyWith(
          processedImagePath: p.join(tmpDir.path, 'after-crop.jpg'),
          filter: PageFilter.blackAndWhite,
          brightness: 0,
          contrast: 0,
          sharpness: 0,
        ),
      );

      await viewModel.reloadFromRepository();

      expect(viewModel.filter, PageFilter.blackAndWhite);
      expect(viewModel.previewImagePath, endsWith('after-crop.jpg'));
      expect(viewModel.showingSavedProcessed, isTrue);
      expect(viewModel.previewEpoch, greaterThan(0));
    },
  );

  test(
    'apply returns false and surfaces an error without crashing on a missing page',
    () async {
      final missingPageViewModel = FilterAdjustmentViewModel(
        pageId: 'does-not-exist',
        pageRepository: pageRepository,
        capturePageUseCase: CapturePageUseCase(
          pageRepository: pageRepository,
          enhancementProvider: enhancementProvider,
          detectionProvider: _FakeDetectionProvider(),
          fileStorage: _FakePaths(),
        ),
      );
      await missingPageViewModel.initialize();

      expect(missingPageViewModel.error, isNotNull);
      expect(await missingPageViewModel.apply(), isFalse);
    },
  );
}
