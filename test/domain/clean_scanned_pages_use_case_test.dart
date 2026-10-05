import 'package:bookscanner/domain/models/geometry.dart';
import 'package:bookscanner/domain/models/provider_info.dart';
import 'package:bookscanner/domain/models/scan_page.dart';
import 'package:bookscanner/domain/providers/image_enhancement_provider.dart';
import 'package:bookscanner/domain/providers/page_detection_provider.dart';
import 'package:bookscanner/domain/repositories/page_path_allocator.dart';
import 'package:bookscanner/domain/repositories/page_repository.dart';
import 'package:bookscanner/domain/use_cases/capture_page_use_case.dart';
import 'package:bookscanner/domain/use_cases/clean_scanned_pages_use_case.dart';
import 'package:flutter_test/flutter_test.dart';

class _Pages implements PageRepository {
  final pages = <String, ScanPage>{};

  @override
  Future<ScanPage?> getPage(String pageId) async => pages[pageId];

  @override
  Future<void> updatePage(ScanPage page) async => pages[page.id] = page;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Enhancer implements ImageEnhancementProvider {
  final requests = <EnhancementRequest>[];
  bool fail = false;

  @override
  ProviderInfo get info =>
      const ProviderInfo(providerName: 'fake', adapterVersion: '1');

  @override
  Future<double> scoreQuality(String imagePath) async => 0.9;

  @override
  Future<EnhancementResult> enhance(EnhancementRequest request) async {
    requests.add(request);
    if (fail) throw StateError('out of memory');
    return EnhancementResult(
      processedImagePath: request.outputImagePath,
      thumbnailPath: '${request.outputImagePath}.thumb',
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
  @override
  String originalPathFor(String pageId, {required String ext}) =>
      '/o/$pageId.$ext';

  @override
  String processedPathFor(String pageId, {required String ext}) =>
      '/p/$pageId.$ext';

  @override
  String thumbnailPathFor(String pageId) => '/t/$pageId.jpg';

  @override
  String exportPathFor(String jobId, String extension) => '/e/$jobId';
}

ScanPage _scan(String id, {PageFilter filter = PageFilter.original}) =>
    ScanPage(
      id: id,
      projectId: 'book',
      sequence: 0,
      originalImagePath: '/o/$id.jpg',
      processedImagePath: '/o/$id.jpg',
      thumbnailPath: '/o/$id.jpg',
      filter: filter,
      status: PageStatus.ready,
    );

void main() {
  late _Pages pages;
  late _Enhancer enhancer;
  late CleanScannedPagesUseCase cleanup;

  setUp(() {
    pages = _Pages();
    enhancer = _Enhancer();
    cleanup = CleanScannedPagesUseCase(
      pageRepository: pages,
      capturePageUseCase: CapturePageUseCase(
        pageRepository: pages,
        enhancementProvider: enhancer,
        detectionProvider: _NoDetection(),
        fileStorage: _Paths(),
      ),
    );
  });

  test('untouched scans are re-rendered with shadow removal', () async {
    pages.pages['a'] = _scan('a');
    pages.pages['b'] = _scan('b');

    cleanup.enqueue(['a', 'b']);
    await cleanup.idle;

    expect(enhancer.requests, hasLength(2));
    for (final request in enhancer.requests) {
      expect(request.removeShadowsAndStains, isTrue);
      expect(request.filter, PageFilter.original);
    }
    expect(pages.pages['a']!.processedImagePath, '/p/a.jpg');
  });

  test('edited and deleted pages are left alone', () async {
    pages.pages['edited'] = _scan('edited', filter: PageFilter.grayscale);

    cleanup.enqueue(['edited', 'deleted']);
    await cleanup.idle;

    expect(enhancer.requests, isEmpty);
  });

  test(
    'a failure keeps the page as scanned and does not stop the queue',
    () async {
      pages.pages['a'] = _scan('a');
      pages.pages['b'] = _scan('b');
      enhancer.fail = true;

      cleanup.enqueue(['a', 'b']);
      await cleanup.idle;

      expect(enhancer.requests, hasLength(2));
      expect(pages.pages['a']!.processedImagePath, '/o/a.jpg');
    },
  );
}
