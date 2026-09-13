import 'dart:io';

import 'package:bookscanner/data/services/export/adapters/fake_pdf_rasterizer_provider.dart';
import 'package:bookscanner/domain/models/ocr_block.dart';
import 'package:bookscanner/domain/models/page_source.dart';
import 'package:bookscanner/domain/models/scan_page.dart';
import 'package:bookscanner/domain/repositories/ocr_repository.dart';
import 'package:bookscanner/domain/repositories/page_repository.dart';
import 'package:bookscanner/domain/repositories/working_session_path_allocator.dart';
import 'package:bookscanner/domain/use_cases/load_page_source_use_case.dart';
import 'package:bookscanner/domain/use_cases/load_project_page_inputs_use_case.dart';
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
  Future<void> deletePage(String pageId) async {}

  @override
  Future<void> duplicatePage(String pageId) async {}

  @override
  Future<void> reorderPages(String projectId, List<String> order) async {}

  @override
  Stream<List<ScanPage>> watchPages(String projectId) => const Stream.empty();
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

class _FakeWorkingSessionPaths implements WorkingSessionPathAllocator {
  _FakeWorkingSessionPaths(this._tmpDir);
  final Directory _tmpDir;

  @override
  String pagePathFor(String sessionId, String pageId, {required String ext}) {
    final dir = Directory(p.join(_tmpDir.path, sessionId))
      ..createSync(recursive: true);
    return p.join(dir.path, '$pageId.$ext');
  }

  @override
  Future<void> clearSession(String sessionId) async {
    final dir = Directory(p.join(_tmpDir.path, sessionId));
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}

void main() {
  late Directory tmpDir;
  late _FakePageRepository pageRepository;
  late FakePdfRasterizerProvider rasterizer;
  late _FakeWorkingSessionPaths workingPaths;
  late LoadPageSourceUseCase useCase;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp(
      'load_page_source_use_case_test_',
    );
    pageRepository = _FakePageRepository();
    rasterizer = FakePdfRasterizerProvider();
    workingPaths = _FakeWorkingSessionPaths(tmpDir);
    useCase = LoadPageSourceUseCase(
      projectLoader: LoadProjectPageInputsUseCase(
        pageRepository: pageRepository,
        ocrRepository: _FakeOcrRepository(),
      ),
      rasterizer: rasterizer,
      workingPaths: workingPaths,
    );
  });

  tearDown(() async {
    if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
  });

  test('ProjectPageSource delegates to the project loader', () async {
    await pageRepository.addPage(
      ScanPage(
        id: 'p1',
        projectId: 'proj1',
        sequence: 0,
        originalImagePath: '/tmp/p1.jpg',
        status: PageStatus.ready,
      ),
    );

    final inputs = await useCase(
      const ProjectPageSource('proj1'),
      sessionId: 'session1',
    );

    expect(inputs, hasLength(1));
    expect(inputs.single.pageId, 'p1');
  });

  test(
    'ExternalPdfPageSource rasterizes every page and writes each to scratch storage',
    () async {
      final inputs = await useCase(
        const ExternalPdfPageSource('/tmp/does-not-matter.pdf'),
        sessionId: 'session1',
      );

      expect(
        inputs,
        hasLength(3),
      ); // FakePdfRasterizerProvider's default page count
      for (final input in inputs) {
        expect(File(input.imagePath).existsSync(), isTrue);
        expect(input.rotationDegrees, 0);
      }
      expect(inputs.map((i) => i.pageId).toSet(), hasLength(3)); // distinct ids
    },
  );

  test(
    'ExternalPdfPageSource with explicit pageIndices imports only those pages',
    () async {
      final inputs = await useCase(
        const ExternalPdfPageSource(
          '/tmp/does-not-matter.pdf',
          pageIndices: [1],
        ),
        sessionId: 'session1',
      );

      expect(inputs, hasLength(1));
    },
  );

  test('ImageFilePageSource copies the file into scratch storage', () async {
    final image = img.Image(width: 50, height: 60);
    img.fill(image, color: img.ColorRgb8(0, 0, 0));
    final sourcePath = p.join(tmpDir.path, 'source.png');
    await File(sourcePath).writeAsBytes(img.encodePng(image));

    final inputs = await useCase(
      ImageFilePageSource(sourcePath),
      sessionId: 'session1',
    );

    expect(inputs, hasLength(1));
    expect(inputs.single.imagePath, isNot(sourcePath));
    expect(File(inputs.single.imagePath).existsSync(), isTrue);
  });
}
