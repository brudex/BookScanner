import 'package:bookscanner/data/repositories/ocr_repository_impl.dart';
import 'package:bookscanner/data/repositories/page_repository_impl.dart';
import 'package:bookscanner/data/repositories/project_repository_impl.dart';
import 'package:bookscanner/domain/models/geometry.dart';
import 'package:bookscanner/domain/models/ocr_block.dart';
import 'package:bookscanner/domain/models/project.dart';
import 'package:bookscanner/domain/models/scan_page.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_database.dart';

void main() {
  late OcrRepositoryImpl ocrRepository;
  late String pageId;
  late String projectId;

  setUp(() async {
    final db = await openTestDatabase();
    ocrRepository = OcrRepositoryImpl(db);
    final projectRepository = ProjectRepositoryImpl(db);
    final pageRepository = PageRepositoryImpl(db);
    final project = await projectRepository.createProject(
      type: ProjectType.document,
      title: 'Doc',
    );
    projectId = project.id;
    await pageRepository.addPage(
      ScanPage(
        id: 'p1',
        projectId: project.id,
        sequence: 0,
        originalImagePath: '/tmp/p1.jpg',
        status: PageStatus.ready,
      ),
    );
    pageId = 'p1';
  });

  Polygon poly() => const Polygon([
    Point2D(x: 0.1, y: 0.1),
    Point2D(x: 0.5, y: 0.1),
    Point2D(x: 0.5, y: 0.2),
    Point2D(x: 0.1, y: 0.2),
  ]);

  test('saveBlocks then getBlocks round-trips in reading order', () async {
    await ocrRepository.saveBlocks(pageId, [
      OcrBlock(
        id: 'b2',
        pageId: pageId,
        boundingPolygon: poly(),
        text: 'Second',
        confidence: 0.9,
        language: 'en',
        blockType: BlockType.paragraph,
        readingOrder: 1,
      ),
      OcrBlock(
        id: 'b1',
        pageId: pageId,
        boundingPolygon: poly(),
        text: 'First',
        confidence: 0.9,
        language: 'en',
        blockType: BlockType.heading,
        readingOrder: 0,
        headingLevel: 1,
      ),
    ]);

    final blocks = await ocrRepository.getBlocks(pageId);
    expect(blocks.map((b) => b.text).toList(), ['First', 'Second']);
    expect(blocks.first.blockType, BlockType.heading);
    expect(blocks.first.headingLevel, 1);
  });

  test(
    'correctBlock records correction history without losing original text',
    () async {
      await ocrRepository.saveBlocks(pageId, [
        OcrBlock(
          id: 'b1',
          pageId: pageId,
          boundingPolygon: poly(),
          text: 'Teh cat',
          confidence: 0.4,
          language: 'en',
          blockType: BlockType.paragraph,
          readingOrder: 0,
        ),
      ]);

      await ocrRepository.correctBlock(pageId, 'b1', 'The cat');

      final blocks = await ocrRepository.getBlocks(pageId);
      expect(blocks.single.text, 'The cat');
      expect(blocks.single.corrections, hasLength(1));
      expect(blocks.single.corrections.single.previousText, 'Teh cat');
    },
  );

  test('searchPages finds pages by OCR text', () async {
    await ocrRepository.saveBlocks(pageId, [
      OcrBlock(
        id: 'b1',
        pageId: pageId,
        boundingPolygon: poly(),
        text: 'The quick brown fox',
        confidence: 0.9,
        language: 'en',
        blockType: BlockType.paragraph,
        readingOrder: 0,
      ),
    ]);

    final results = await ocrRepository.searchPages(projectId, 'quick');
    expect(results, [pageId]);

    final noMatch = await ocrRepository.searchPages(projectId, 'zzz');
    expect(noMatch, isEmpty);
  });

  test('hasOcr reflects presence of saved blocks', () async {
    expect(await ocrRepository.hasOcr(pageId), isFalse);
    await ocrRepository.saveBlocks(pageId, [
      OcrBlock(
        id: 'b1',
        pageId: pageId,
        boundingPolygon: poly(),
        text: 'x',
        confidence: 0.9,
        language: 'en',
        blockType: BlockType.paragraph,
        readingOrder: 0,
      ),
    ]);
    expect(await ocrRepository.hasOcr(pageId), isTrue);
  });
}
