import 'package:bookscanner/domain/models/ocr_block.dart';
import 'package:bookscanner/domain/models/scan_page.dart';
import 'package:bookscanner/domain/repositories/ocr_repository.dart';
import 'package:bookscanner/domain/repositories/page_repository.dart';
import 'package:bookscanner/domain/use_cases/load_project_page_inputs_use_case.dart';
import 'package:flutter_test/flutter_test.dart';

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
      pages.values.where((p) => p.projectId == projectId).toList()
        ..sort((a, b) => a.sequence.compareTo(b.sequence));

  @override
  Future<void> deletePage(String pageId) async {}

  @override
  Future<void> duplicatePage(String pageId) async {}

  @override
  Future<void> reorderPages(String projectId, List<String> order) async {}

  @override
  Stream<List<ScanPage>> watchPages(String projectId) => const Stream.empty();
}

class _FakeOcrRepository implements OcrRepository {
  final blocksByPage = <String, List<OcrBlock>>{};

  @override
  Future<List<OcrBlock>> getBlocks(String pageId) async =>
      blocksByPage[pageId] ?? const [];

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
  late _FakeOcrRepository ocrRepository;
  late LoadProjectPageInputsUseCase useCase;

  setUp(() {
    pageRepository = _FakePageRepository();
    ocrRepository = _FakeOcrRepository();
    useCase = LoadProjectPageInputsUseCase(
      pageRepository: pageRepository,
      ocrRepository: ocrRepository,
    );
  });

  test(
    'falls back to originalImagePath when processedImagePath is null',
    () async {
      await pageRepository.addPage(
        ScanPage(
          id: 'p1',
          projectId: 'proj1',
          sequence: 0,
          originalImagePath: '/tmp/original.jpg',
          status: PageStatus.ready,
        ),
      );

      final inputs = await useCase('proj1');

      expect(inputs, hasLength(1));
      expect(inputs.single.imagePath, '/tmp/original.jpg');
    },
  );

  test('prefers processedImagePath when present', () async {
    await pageRepository.addPage(
      ScanPage(
        id: 'p1',
        projectId: 'proj1',
        sequence: 0,
        originalImagePath: '/tmp/original.jpg',
        processedImagePath: '/tmp/processed.jpg',
        status: PageStatus.ready,
      ),
    );

    final inputs = await useCase('proj1');

    expect(inputs.single.imagePath, '/tmp/processed.jpg');
  });

  test(
    'carries rotationDegrees, logicalPageLabel, and ocrBlocks through',
    () async {
      await pageRepository.addPage(
        ScanPage(
          id: 'p1',
          projectId: 'proj1',
          sequence: 0,
          originalImagePath: '/tmp/original.jpg',
          rotationDegrees: 90,
          logicalPageLabel: 'iv',
          status: PageStatus.ready,
        ),
      );
      ocrRepository.blocksByPage['p1'] = [
        OcrBlock(
          id: 'b1',
          pageId: 'p1',
          boundingPolygon: const Polygon([]),
          text: 'Hello',
          confidence: 0.9,
          language: 'en',
          blockType: BlockType.paragraph,
          readingOrder: 0,
        ),
      ];

      final inputs = await useCase('proj1');

      expect(inputs.single.rotationDegrees, 90);
      expect(inputs.single.logicalPageLabel, 'iv');
      expect(inputs.single.ocrBlocks, hasLength(1));
      expect(inputs.single.ocrBlocks.single.text, 'Hello');
    },
  );

  test('returns pages in sequence order', () async {
    await pageRepository.addPage(
      ScanPage(
        id: 'p2',
        projectId: 'proj1',
        sequence: 1,
        originalImagePath: '/tmp/p2.jpg',
        status: PageStatus.ready,
      ),
    );
    await pageRepository.addPage(
      ScanPage(
        id: 'p1',
        projectId: 'proj1',
        sequence: 0,
        originalImagePath: '/tmp/p1.jpg',
        status: PageStatus.ready,
      ),
    );

    final inputs = await useCase('proj1');

    expect(inputs.map((i) => i.pageId).toList(), ['p1', 'p2']);
  });
}
