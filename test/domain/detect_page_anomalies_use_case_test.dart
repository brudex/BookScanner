import 'dart:async';
import 'dart:io';

import 'package:bookscanner/domain/models/ocr_block.dart';
import 'package:bookscanner/domain/models/scan_page.dart';
import 'package:bookscanner/domain/repositories/ocr_repository.dart';
import 'package:bookscanner/domain/repositories/page_repository.dart';
import 'package:bookscanner/domain/use_cases/detect_page_anomalies_use_case.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

class _FakePageRepository implements PageRepository {
  final _pages = <String, ScanPage>{};

  void seed(List<ScanPage> pages) {
    for (final page in pages) {
      _pages[page.id] = page;
    }
  }

  @override
  Future<List<ScanPage>> getPages(String projectId) async =>
      _pages.values.where((p) => p.projectId == projectId).toList()
        ..sort((a, b) => a.sequence.compareTo(b.sequence));

  @override
  Future<void> updatePage(ScanPage page) async => _pages[page.id] = page;

  @override
  Future<void> addPage(ScanPage page) async => _pages[page.id] = page;

  @override
  Future<ScanPage?> getPage(String pageId) async => _pages[pageId];

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

class _FakeOcrRepository implements OcrRepository {
  final _blocks = <String, List<OcrBlock>>{};

  void seedText(String pageId, String text) {
    _blocks[pageId] = [
      OcrBlock(
        id: '$pageId-block',
        pageId: pageId,
        boundingPolygon: const Polygon([]),
        text: text,
        confidence: 0.9,
        language: 'en',
        blockType: BlockType.paragraph,
        readingOrder: 0,
      ),
    ];
  }

  @override
  Future<List<OcrBlock>> getBlocks(String pageId) async =>
      _blocks[pageId] ?? const [];

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
  Future<bool> hasOcr(String pageId) async => _blocks.containsKey(pageId);

  @override
  Future<List<String>> searchPages(String projectId, String query) async =>
      const [];
}

void main() {
  // DetectPageAnomaliesUseCase now hashes pages via compute(), which needs
  // a Flutter binding initialized even for pure-Dart isolate work with no
  // platform channels involved.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmpDir;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('anomaly_test_');
  });

  tearDown(() async {
    if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
  });

  Future<String> writeImage(String name, {required int parity}) async {
    final image = img.Image(width: 64, height: 64);
    // 8x8 checkerboard with real internal light/dark variance (so the
    // average-hash's "brighter than the image's own mean" comparison is
    // meaningful, unlike a solid/uniform image, which degenerates to an
    // all-zero hash regardless of its absolute brightness). `parity` shifts
    // which cells are light vs dark: parity 0 vs 1 is a full per-cell
    // inversion, which is the maximally-different case a duplicate
    // detector must NOT confuse with a real duplicate (parity 0 vs 0).
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        final light = (x + y + parity) % 2 == 0;
        img.fillRect(
          image,
          x1: x * 8,
          y1: y * 8,
          x2: x * 8 + 7,
          y2: y * 8 + 7,
          color: light
              ? img.ColorRgb8(235, 235, 235)
              : img.ColorRgb8(20, 20, 20),
        );
      }
    }
    final path = p.join(tmpDir.path, name);
    await File(path).writeAsBytes(img.encodeJpg(image));
    return path;
  }

  test(
    'flags near-identical pages as duplicates via perceptual hash',
    () async {
      final repository = _FakePageRepository();
      final imgA = await writeImage('a.jpg', parity: 0);
      final imgB = await writeImage('b.jpg', parity: 0);
      final imgC = await writeImage(
        'c.jpg',
        parity: 1,
      ); // fully inverted checkerboard

      repository.seed([
        ScanPage(
          id: 'p1',
          projectId: 'proj',
          sequence: 0,
          originalImagePath: imgA,
          status: PageStatus.ready,
        ),
        ScanPage(
          id: 'p2',
          projectId: 'proj',
          sequence: 1,
          originalImagePath: imgB,
          status: PageStatus.ready,
        ),
        ScanPage(
          id: 'p3',
          projectId: 'proj',
          sequence: 2,
          originalImagePath: imgC,
          status: PageStatus.ready,
        ),
      ]);

      final useCase = DetectPageAnomaliesUseCase(
        pageRepository: repository,
        ocrRepository: _FakeOcrRepository(),
      );
      final result = await useCase.analyze('proj');

      expect(result.duplicatesOf['p2'], 'p1');
      expect(result.duplicatesOf.containsKey('p3'), isFalse);
    },
  );

  test(
    'flags pages with near-identical OCR text as duplicates even when the image hash misses them '
    '(different crop/lighting/rotation of the same physical page)',
    () async {
      final repository = _FakePageRepository();
      final ocrRepository = _FakeOcrRepository();
      // p1/p2 use opposite checkerboard parity -- already established by
      // the test above as visually distinct enough that the perceptual
      // image hash alone does NOT flag them as duplicates (that's exactly
      // the gap this text-similarity signal exists to cover). p3 is a
      // uniform fill, visually distinct from both.
      final imgA = await writeImage('a.jpg', parity: 0);
      final imgB = await writeImage('b.jpg', parity: 1);
      final plain = img.Image(width: 64, height: 64);
      img.fill(plain, color: img.ColorRgb8(128, 128, 128));
      final imgCPath = p.join(tmpDir.path, 'c.jpg');
      await File(imgCPath).writeAsBytes(img.encodeJpg(plain));

      repository.seed([
        ScanPage(
          id: 'p1',
          projectId: 'proj',
          sequence: 0,
          originalImagePath: imgA,
          status: PageStatus.ready,
        ),
        ScanPage(
          id: 'p2',
          projectId: 'proj',
          sequence: 1,
          originalImagePath: imgB,
          status: PageStatus.ready,
        ),
        ScanPage(
          id: 'p3',
          projectId: 'proj',
          sequence: 2,
          originalImagePath: imgCPath,
          status: PageStatus.ready,
        ),
      ]);
      ocrRepository.seedText(
        'p1',
        'The quick brown fox jumps over the lazy dog',
      );
      ocrRepository.seedText(
        'p2',
        'The quick brown fox jumps over the lazy dog',
      );
      ocrRepository.seedText(
        'p3',
        'A completely different paragraph about something else entirely',
      );

      final useCase = DetectPageAnomaliesUseCase(
        pageRepository: repository,
        ocrRepository: ocrRepository,
      );
      final result = await useCase.analyze('proj');

      expect(result.duplicatesOf['p2'], 'p1');
      expect(result.duplicatesOf.containsKey('p3'), isFalse);
    },
  );

  test(
    'does not run the text-similarity check for pages with no OCR yet',
    () async {
      final repository = _FakePageRepository();
      final imgA = await writeImage('a.jpg', parity: 0);
      final imgB = await writeImage('b.jpg', parity: 1);
      repository.seed([
        ScanPage(
          id: 'p1',
          projectId: 'proj',
          sequence: 0,
          originalImagePath: imgA,
          status: PageStatus.ready,
        ),
        ScanPage(
          id: 'p2',
          projectId: 'proj',
          sequence: 1,
          originalImagePath: imgB,
          status: PageStatus.ready,
        ),
      ]);

      final useCase = DetectPageAnomaliesUseCase(
        pageRepository: repository,
        ocrRepository: _FakeOcrRepository(),
      );
      final result = await useCase.analyze('proj');

      expect(result.duplicatesOf, isEmpty);
    },
  );

  test(
    'flags a likely missing page from a gap in printed page numbers',
    () async {
      final repository = _FakePageRepository();
      final path = await writeImage('x.jpg', parity: 0);
      repository.seed([
        ScanPage(
          id: 'p1',
          projectId: 'proj',
          sequence: 0,
          originalImagePath: path,
          status: PageStatus.ready,
          logicalPageLabel: '1',
        ),
        ScanPage(
          id: 'p2',
          projectId: 'proj',
          sequence: 1,
          originalImagePath: path,
          status: PageStatus.ready,
          logicalPageLabel: '4',
        ),
      ]);

      final useCase = DetectPageAnomaliesUseCase(
        pageRepository: repository,
        ocrRepository: _FakeOcrRepository(),
      );
      final result = await useCase.analyze('proj');

      expect(result.likelyMissingBeforeSequence, contains(1));
    },
  );

  test('does not flag consecutive page numbers as missing', () async {
    final repository = _FakePageRepository();
    final path = await writeImage('y.jpg', parity: 0);
    repository.seed([
      ScanPage(
        id: 'p1',
        projectId: 'proj',
        sequence: 0,
        originalImagePath: path,
        status: PageStatus.ready,
        logicalPageLabel: '1',
      ),
      ScanPage(
        id: 'p2',
        projectId: 'proj',
        sequence: 1,
        originalImagePath: path,
        status: PageStatus.ready,
        logicalPageLabel: '2',
      ),
    ]);

    final useCase = DetectPageAnomaliesUseCase(
      pageRepository: repository,
      ocrRepository: _FakeOcrRepository(),
    );
    final result = await useCase.analyze('proj');

    expect(result.likelyMissingBeforeSequence, isEmpty);
  });
}
