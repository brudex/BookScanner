import 'dart:io';

import 'package:bookscanner/data/services/export/adapters/fake_pdf_rasterizer_provider.dart';
import 'package:bookscanner/domain/models/geometry.dart';
import 'package:bookscanner/domain/models/provider_info.dart';
import 'package:bookscanner/domain/models/scan_page.dart';
import 'package:bookscanner/domain/providers/image_enhancement_provider.dart';
import 'package:bookscanner/domain/providers/page_detection_provider.dart';
import 'package:bookscanner/domain/repositories/page_path_allocator.dart';
import 'package:bookscanner/domain/repositories/page_repository.dart';
import 'package:bookscanner/domain/use_cases/capture_page_use_case.dart';
import 'package:bookscanner/domain/use_cases/import_pages_use_case.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _FakePageRepository implements PageRepository {
  final pages = <String, ScanPage>{};

  @override
  Future<void> addPage(ScanPage page) async => pages[page.id] = page;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PassthroughEnhancement implements ImageEnhancementProvider {
  @override
  ProviderInfo get info =>
      const ProviderInfo(providerName: 'fake', adapterVersion: '1');

  @override
  Future<double> scoreQuality(String imagePath) async => 0.9;

  @override
  Future<EnhancementResult> enhance(EnhancementRequest request) async {
    await File(request.sourceImagePath).copy(request.outputImagePath);
    return EnhancementResult(
      processedImagePath: request.outputImagePath,
      thumbnailPath: request.outputImagePath,
      qualityScore: 0.9,
      providerInfo: info,
      cropPoints: Quad.fullFrame,
    );
  }
}

class _NoDetection implements PageDetectionProvider {
  @override
  ProviderInfo get info =>
      const ProviderInfo(providerName: 'fake', adapterVersion: '1');

  @override
  Future<Quad?> detectQuad(String imagePath) async => null;
}

class _Paths implements PagePathAllocator {
  _Paths(this.root);
  final Directory root;

  @override
  String originalPathFor(String pageId, {required String ext}) =>
      p.join(root.path, 'originals', '$pageId.$ext');

  @override
  String processedPathFor(String pageId, {required String ext}) =>
      p.join(root.path, 'processed', '$pageId.$ext');

  @override
  String thumbnailPathFor(String pageId) =>
      p.join(root.path, 'thumbnails', '$pageId.jpg');

  @override
  String exportPathFor(String jobId, String extension) =>
      p.join(root.path, '$jobId.$extension');
}

void main() {
  late Directory root;
  late _FakePageRepository pages;
  late List<(String, String)> stored;
  late ImportPagesUseCase useCase;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('import_pages_test_');
    Directory(p.join(root.path, 'processed')).createSync();
    pages = _FakePageRepository();
    stored = [];
    final paths = _Paths(root);
    useCase = ImportPagesUseCase(
      capturePageUseCase: CapturePageUseCase(
        pageRepository: pages,
        enhancementProvider: _PassthroughEnhancement(),
        detectionProvider: _NoDetection(),
        fileStorage: paths,
      ),
      paths: paths,
      rasterizer: FakePdfRasterizerProvider(defaultPageCount: 2),
      storeImage: (source, dest) async {
        stored.add((source, dest));
        await File(source).copy(dest);
      },
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('gallery images are copied into app storage, never kept in the '
      'picker cache, and added in order', () async {
    final cache = Directory(p.join(root.path, 'cache'))..createSync();
    final a = File(p.join(cache.path, 'a.jpg'))..writeAsBytesSync([1]);
    final b = File(p.join(cache.path, 'b.jpg'))..writeAsBytesSync([2]);

    final added = await useCase.importImages(
      [a.path, b.path],
      projectId: 'proj',
      startSequence: 5,
    );

    expect(added.map((page) => page.sequence), [5, 6]);
    expect(stored.map((s) => s.$1), [a.path, b.path]);
    for (final page in added) {
      expect(
        page.originalImagePath,
        startsWith(p.join(root.path, 'originals')),
      );
      expect(File(page.originalImagePath).existsSync(), isTrue);
    }
    // The page survives the picker cache being cleared.
    cache.deleteSync(recursive: true);
    expect(File(added.first.originalImagePath).existsSync(), isTrue);
  });

  test('every PDF page becomes a stored page, in order', () async {
    final added = await useCase.importPdf(
      '/any.pdf',
      projectId: 'proj',
      startSequence: 0,
    );

    expect(added.map((page) => page.sequence), [0, 1]);
    for (final page in added) {
      expect(File(page.originalImagePath).existsSync(), isTrue);
    }
    expect(pages.pages, hasLength(2));
  });

  test('a failing copy surfaces as an error, not a half-saved page', () async {
    final failing = ImportPagesUseCase(
      capturePageUseCase: CapturePageUseCase(
        pageRepository: pages,
        enhancementProvider: _PassthroughEnhancement(),
        detectionProvider: _NoDetection(),
        fileStorage: _Paths(root),
      ),
      paths: _Paths(root),
      rasterizer: FakePdfRasterizerProvider(),
      storeImage: (source, dest) async =>
          throw const FileSystemException('disk full'),
    );

    await expectLater(
      failing.importImages(
        ['/missing.jpg'],
        projectId: 'proj',
        startSequence: 0,
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(pages.pages, isEmpty);
  });
}
