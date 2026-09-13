import 'dart:async';
import 'dart:io';

import 'package:bookscanner/data/services/export/dart_document_export_provider.dart';
import 'package:bookscanner/domain/models/export_job.dart';
import 'package:bookscanner/domain/models/ocr_block.dart';
import 'package:bookscanner/domain/models/scan_page.dart';
import 'package:bookscanner/domain/providers/document_export_provider.dart';
import 'package:bookscanner/domain/repositories/export_job_repository.dart';
import 'package:bookscanner/domain/repositories/ocr_repository.dart';
import 'package:bookscanner/domain/repositories/page_path_allocator.dart';
import 'package:bookscanner/domain/repositories/page_repository.dart';
import 'package:bookscanner/domain/use_cases/export_project_use_case.dart';
import 'package:bookscanner/domain/use_cases/load_project_page_inputs_use_case.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

// Regression guard for extracting the page-loading loop out of
// ExportProjectUseCase.export() into LoadProjectPageInputsUseCase: the
// default (no loader passed) behavior must stay byte-identical, and a
// caller-supplied loader must be honored.

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

class _FakeExportJobRepository implements ExportJobRepository {
  final jobs = <String, ExportJob>{};

  @override
  Future<ExportJob> createJob(ExportJob job) async {
    jobs[job.id] = job;
    return job;
  }

  @override
  Future<void> updateJob(ExportJob job) async => jobs[job.id] = job;

  @override
  Future<void> cancelJob(String jobId) async {}

  @override
  Stream<ExportJob?> watchJob(String jobId) => Stream.value(jobs[jobId]);

  @override
  Stream<List<ExportJob>> watchJobsForProject(String projectId) =>
      const Stream.empty();
}

class _FakePaths implements PagePathAllocator {
  _FakePaths(this._tmpDir);
  final Directory _tmpDir;

  @override
  String originalPathFor(String pageId, {required String ext}) =>
      p.join(_tmpDir.path, '$pageId-original.$ext');

  @override
  String processedPathFor(String pageId, {required String ext}) =>
      p.join(_tmpDir.path, '$pageId-processed.$ext');

  @override
  String thumbnailPathFor(String pageId) =>
      p.join(_tmpDir.path, '$pageId-thumb.jpg');

  @override
  String exportPathFor(String jobId, String extension) =>
      p.join(_tmpDir.path, '$jobId.$extension');
}

void main() {
  late Directory tmpDir;
  late _FakePageRepository pageRepository;
  late _FakeOcrRepository ocrRepository;
  late _FakeExportJobRepository exportJobRepository;
  late String imagePath;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp(
      'export_project_use_case_test_',
    );
    pageRepository = _FakePageRepository();
    ocrRepository = _FakeOcrRepository();
    exportJobRepository = _FakeExportJobRepository();

    final image = img.Image(width: 200, height: 300);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    imagePath = p.join(tmpDir.path, 'page1.jpg');
    await File(imagePath).writeAsBytes(img.encodeJpg(image));
    await pageRepository.addPage(
      ScanPage(
        id: 'p1',
        projectId: 'proj1',
        sequence: 0,
        originalImagePath: imagePath,
        processedImagePath: imagePath,
        status: PageStatus.ready,
      ),
    );
  });

  tearDown(() async {
    if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
  });

  test(
    'with no pageInputLoader passed, default behavior is unchanged: exports the project\'s own pages',
    () async {
      final useCase = ExportProjectUseCase(
        pageRepository: pageRepository,
        ocrRepository: ocrRepository,
        exportJobRepository: exportJobRepository,
        exportProvider: DartDocumentExportProvider(),
        paths: _FakePaths(tmpDir),
      );

      final job = await useCase.export(
        projectId: 'proj1',
        title: 'Test',
        format: ExportFormat.imagePdf,
      );

      expect(job.status, ExportJobStatus.completed);
      expect(File(job.outputPath!).existsSync(), isTrue);
    },
  );

  test(
    'a custom pageInputLoader is honored instead of the project\'s real pages',
    () async {
      final spyLoader = _SpyLoader(
        pageRepository: pageRepository,
        ocrRepository: ocrRepository,
      );

      final useCase = ExportProjectUseCase(
        pageRepository: pageRepository,
        ocrRepository: ocrRepository,
        exportJobRepository: exportJobRepository,
        exportProvider: DartDocumentExportProvider(),
        paths: _FakePaths(tmpDir),
        pageInputLoader: spyLoader,
      );

      final job = await useCase.export(
        projectId: 'proj1',
        title: 'Test',
        format: ExportFormat.imagePdf,
      );

      expect(spyLoader.callCount, 1);
      expect(spyLoader.lastProjectId, 'proj1');
      expect(job.status, ExportJobStatus.completed);
    },
  );
}

/// Records invocations so the "custom loader is honored" test can verify
/// `ExportProjectUseCase` actually calls the supplied loader instead of
/// building its own default one.
class _SpyLoader extends LoadProjectPageInputsUseCase {
  _SpyLoader({required super.pageRepository, required super.ocrRepository});

  int callCount = 0;
  String? lastProjectId;

  @override
  Future<List<ExportPageInput>> call(String projectId) {
    callCount++;
    lastProjectId = projectId;
    return super.call(projectId);
  }
}
