import 'package:bookscanner/domain/models/geometry.dart';
import 'package:bookscanner/domain/models/ocr_block.dart';
import 'package:bookscanner/domain/models/provider_info.dart';
import 'package:bookscanner/domain/models/scan_page.dart';
import 'package:bookscanner/domain/providers/image_enhancement_provider.dart';
import 'package:bookscanner/domain/providers/page_detection_provider.dart';
import 'package:bookscanner/domain/repositories/ocr_repository.dart';
import 'package:bookscanner/domain/repositories/page_path_allocator.dart';
import 'package:bookscanner/domain/repositories/page_repository.dart';
import 'package:bookscanner/domain/use_cases/capture_page_use_case.dart';
import 'package:bookscanner/domain/use_cases/detect_page_anomalies_use_case.dart';
import 'package:bookscanner/ui/features/page_review/view_models/page_review_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

// `CapturePageUseCase` is a required PageReviewViewModel dependency (for
// `revertToOriginal`) but no test in this file exercises that method yet, so
// these fakes are unused-but-present stand-ins, not exercised behavior.
class _FakeImageEnhancementProvider implements ImageEnhancementProvider {
  @override
  ProviderInfo get info =>
      const ProviderInfo(providerName: 'fake', adapterVersion: '1.0.0');

  @override
  Future<EnhancementResult> enhance(EnhancementRequest request) =>
      throw UnimplementedError();

  @override
  Future<double> scoreQuality(String imagePath) => throw UnimplementedError();
}

class _FakePageDetectionProvider implements PageDetectionProvider {
  @override
  ProviderInfo get info =>
      const ProviderInfo(providerName: 'fake', adapterVersion: '1.0.0');

  @override
  Future<Quad?> detectQuad(String imagePath) => throw UnimplementedError();
}

class _FakePagePathAllocator implements PagePathAllocator {
  @override
  String originalPathFor(String pageId, {required String ext}) =>
      throw UnimplementedError();

  @override
  String processedPathFor(String pageId, {required String ext}) =>
      throw UnimplementedError();

  @override
  String thumbnailPathFor(String pageId) => throw UnimplementedError();

  @override
  String exportPathFor(String jobId, String extension) =>
      throw UnimplementedError();
}

// PageReviewViewModel had no dedicated unit tests before this file --
// reorder/rotate/duplicate/delete/gridView were only reachable (and only
// implicitly exercised) through page_review_screen_test.dart's single
// Export-button regression test.

class _FakePageRepository implements PageRepository {
  final pages = <String, ScanPage>{};
  final reorderCalls = <List<String>>[];

  @override
  Future<ScanPage?> getPage(String pageId) async => pages[pageId];

  @override
  Future<void> addPage(ScanPage page) async => pages[page.id] = page;

  @override
  Future<void> updatePage(ScanPage page) async => pages[page.id] = page;

  @override
  Future<List<ScanPage>> getPages(String projectId) async =>
      pages.values.where((p) => p.projectId == projectId).toList()
        ..sort((a, b) => a.sequence.compareTo(b.sequence));

  @override
  Future<void> deletePage(String pageId) async => pages.remove(pageId);

  @override
  Future<void> duplicatePage(String pageId) async {
    final source = pages[pageId];
    if (source == null) return;
    pages['$pageId-copy'] = source.copyWith();
  }

  @override
  Future<void> reorderPages(
    String projectId,
    List<String> newPageIdOrder,
  ) async {
    reorderCalls.add(newPageIdOrder);
  }

  @override
  Stream<List<ScanPage>> watchPages(String projectId) => Stream.value(
    pages.values.where((p) => p.projectId == projectId).toList()
      ..sort((a, b) => a.sequence.compareTo(b.sequence)),
  );
}

class _FakeOcrRepository implements OcrRepository {
  @override
  Future<List<OcrBlock>> getBlocks(String pageId) async => const [];

  @override
  Stream<List<OcrBlock>> watchBlocks(String pageId) => const Stream.empty();

  @override
  Future<void> saveBlocks(String pageId, List<OcrBlock> blocks) async {}

  @override
  Future<void> correctBlock(
    String pageId,
    String blockId,
    String newText,
  ) async {}

  @override
  Future<bool> hasOcr(String pageId) async => false;

  @override
  Future<List<String>> searchPages(String projectId, String query) async =>
      const [];
}

void main() {
  late _FakePageRepository pageRepository;
  late PageReviewViewModel viewModel;

  setUp(() async {
    pageRepository = _FakePageRepository();
    await pageRepository.addPage(
      const ScanPage(
        id: 'p1',
        projectId: 'proj1',
        sequence: 0,
        originalImagePath: '/tmp/p1.jpg',
        status: PageStatus.ready,
      ),
    );
    await pageRepository.addPage(
      const ScanPage(
        id: 'p2',
        projectId: 'proj1',
        sequence: 1,
        originalImagePath: '/tmp/p2.jpg',
        status: PageStatus.ready,
      ),
    );
    viewModel = PageReviewViewModel(
      projectId: 'proj1',
      pageRepository: pageRepository,
      detectAnomaliesUseCase: DetectPageAnomaliesUseCase(
        pageRepository: pageRepository,
        ocrRepository: _FakeOcrRepository(),
      ),
      capturePageUseCase: CapturePageUseCase(
        pageRepository: pageRepository,
        enhancementProvider: _FakeImageEnhancementProvider(),
        detectionProvider: _FakePageDetectionProvider(),
        fileStorage: _FakePagePathAllocator(),
      ),
    );
    // watchPages() emits asynchronously (via a microtask) -- wait a beat so
    // the ViewModel's internal `_pages` list is populated before each test
    // runs.
    await Future<void>.delayed(Duration.zero);
  });

  test(
    'initial pages are loaded from the seeded repository, in sequence order',
    () {
      expect(viewModel.loading, isFalse);
      expect(viewModel.pages.map((p) => p.id).toList(), ['p1', 'p2']);
    },
  );

  test('reorder moves a page locally and persists the new order', () async {
    await viewModel.reorder(0, 2);

    expect(viewModel.pages.map((p) => p.id).toList(), ['p2', 'p1']);
    expect(pageRepository.reorderCalls, isNotEmpty);
    expect(pageRepository.reorderCalls.last, ['p2', 'p1']);
  });

  test('toggleGridView flips between list and grid', () {
    expect(viewModel.gridView, isFalse);
    viewModel.toggleGridView();
    expect(viewModel.gridView, isTrue);
    viewModel.toggleGridView();
    expect(viewModel.gridView, isFalse);
  });

  test('rotate advances only the targeted page by 90 degrees', () async {
    final page = pageRepository.pages['p1']!;
    await viewModel.rotate(page);

    expect(pageRepository.pages['p1']!.rotationDegrees, 90);
    expect(pageRepository.pages['p2']!.rotationDegrees, 0);
  });

  test('duplicate delegates to the repository for that page id', () async {
    final page = pageRepository.pages['p1']!;
    await viewModel.duplicate(page);

    expect(pageRepository.pages.containsKey('p1-copy'), isTrue);
  });

  test('delete removes the targeted page via the repository', () async {
    final page = pageRepository.pages['p1']!;
    await viewModel.delete(page);

    expect(pageRepository.pages.containsKey('p1'), isFalse);
    expect(pageRepository.pages.containsKey('p2'), isTrue);
  });

  test('dismissWarning adds to the page\'s dismissedWarnings set', () async {
    final page = pageRepository.pages['p1']!;
    await viewModel.dismissWarning(page, 'duplicate');

    expect(
      pageRepository.pages['p1']!.dismissedWarnings,
      contains('duplicate'),
    );
  });

  test('setLogicalPageLabel persists a free-form cover/Roman label', () async {
    final page = pageRepository.pages['p1']!;
    await viewModel.setLogicalPageLabel(page, 'iii');

    expect(pageRepository.pages['p1']!.logicalPageLabel, 'iii');
  });

  test('setLogicalPageLabel clears blank labels', () async {
    final page = pageRepository.pages['p1']!;
    await viewModel.setLogicalPageLabel(page, 'Cover');
    await viewModel.setLogicalPageLabel(page, '   ');

    expect(pageRepository.pages['p1']!.logicalPageLabel, isNull);
  });
}
