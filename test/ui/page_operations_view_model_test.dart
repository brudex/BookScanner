import 'dart:io';

import 'package:bookscanner/data/services/export/adapters/fake_pdf_rasterizer_provider.dart';
import 'package:bookscanner/data/services/export/dart_document_export_provider.dart';
import 'package:bookscanner/domain/models/export_job.dart';
import 'package:bookscanner/domain/models/ocr_block.dart';
import 'package:bookscanner/domain/models/page_source.dart';
import 'package:bookscanner/domain/models/scan_page.dart';
import 'package:bookscanner/domain/repositories/export_job_repository.dart';
import 'package:bookscanner/domain/repositories/ocr_repository.dart';
import 'package:bookscanner/domain/repositories/page_path_allocator.dart';
import 'package:bookscanner/domain/repositories/page_repository.dart';
import 'package:bookscanner/domain/repositories/working_session_path_allocator.dart';
import 'package:bookscanner/domain/use_cases/export_page_inputs_use_case.dart';
import 'package:bookscanner/domain/use_cases/load_page_source_use_case.dart';
import 'package:bookscanner/domain/use_cases/load_project_page_inputs_use_case.dart';
import 'package:bookscanner/ui/features/page_operations/view_models/page_operations_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

// Plain test()s, not testWidgets(): this ViewModel drives real dart:io PDF
// export directly (no live job-stream StreamSubscription, unlike
// ExportViewModel), so there's no fake-async/runAsync hazard to work around
// here -- see export_view_model_test.dart's doc comment for why that
// distinction matters in this codebase.

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

class _FakeWorkingSessionPaths implements WorkingSessionPathAllocator {
  _FakeWorkingSessionPaths(this._tmpDir);
  final Directory _tmpDir;
  final clearedSessions = <String>[];

  @override
  String pagePathFor(String sessionId, String pageId, {required String ext}) {
    final dir = Directory(p.join(_tmpDir.path, sessionId))
      ..createSync(recursive: true);
    return p.join(dir.path, '$pageId.$ext');
  }

  @override
  Future<void> clearSession(String sessionId) async {
    clearedSessions.add(sessionId);
    final dir = Directory(p.join(_tmpDir.path, sessionId));
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}

/// Exact page-object count. "/Type /Page" alone over-counts by 1 (the
/// document's single "/Type /Pages" tree root also matches that substring),
/// which is why `dart_document_export_provider_test.dart` only asserts
/// `greaterThanOrEqualTo` with it -- this helper subtracts that known
/// constant offset so exact-count assertions (e.g. "extract produced exactly
/// 1 page") are meaningful here.
int _pdfPageCount(List<int> bytes) {
  final text = String.fromCharCodes(bytes);
  final pageMatches =
      '/Type /Page'.allMatches(text).length +
      '/Type/Page'.allMatches(text).length;
  final pagesTreeMatches =
      '/Type /Pages'.allMatches(text).length +
      '/Type/Pages'.allMatches(text).length;
  return pageMatches - pagesTreeMatches;
}

void main() {
  late Directory tmpDir;
  late _FakePageRepository pageRepository;
  late _FakeWorkingSessionPaths workingPaths;
  late PageOperationsViewModel viewModel;
  late String pageAPath;
  late String pageBPath;

  Future<String> writeJpg(String name) async {
    final image = img.Image(width: 100, height: 150);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    final path = p.join(tmpDir.path, name);
    await File(path).writeAsBytes(img.encodeJpg(image));
    return path;
  }

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp(
      'page_operations_view_model_test_',
    );
    pageRepository = _FakePageRepository();
    workingPaths = _FakeWorkingSessionPaths(tmpDir);

    pageAPath = await writeJpg('a.jpg');
    pageBPath = await writeJpg('b.jpg');
    await pageRepository.addPage(
      ScanPage(
        id: 'a',
        projectId: 'proj1',
        sequence: 0,
        originalImagePath: pageAPath,
        status: PageStatus.ready,
      ),
    );
    await pageRepository.addPage(
      ScanPage(
        id: 'b',
        projectId: 'proj1',
        sequence: 1,
        originalImagePath: pageBPath,
        status: PageStatus.ready,
      ),
    );

    final projectLoader = LoadProjectPageInputsUseCase(
      pageRepository: pageRepository,
      ocrRepository: _FakeOcrRepository(),
    );
    viewModel = PageOperationsViewModel(
      hostProjectId: 'proj1',
      projectPageLoader: projectLoader,
      pageSourceLoader: LoadPageSourceUseCase(
        projectLoader: projectLoader,
        rasterizer: FakePdfRasterizerProvider(),
        workingPaths: workingPaths,
      ),
      exportUseCase: ExportPageInputsUseCase(
        exportJobRepository: _FakeExportJobRepository(),
        exportProvider: DartDocumentExportProvider(),
        paths: _FakePaths(tmpDir),
      ),
      workingPaths: workingPaths,
      rasterizer: FakePdfRasterizerProvider(),
    );
    await viewModel.initialize();
  });

  tearDown(() async {
    try {
      if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
    } on PathNotFoundException {
      // The dispose() test below triggers an unawaited, concurrent
      // clearSession() deletion of a subdirectory; harmless if it races
      // with this cleanup and wins.
    }
  });

  test('initialize loads the host project\'s own pages', () {
    expect(viewModel.pages.map((p) => p.pageId).toList(), ['a', 'b']);
  });

  test('reorder moves a page', () {
    viewModel.reorder(
      0,
      2,
    ); // ReorderableListView passes the post-removal target index
    expect(viewModel.pages.map((p) => p.pageId).toList(), ['b', 'a']);
  });

  test('rotate advances rotationDegrees by 90 for only the targeted page', () {
    viewModel.rotate('a');
    expect(viewModel.pages[0].rotationDegrees, 90);
    expect(viewModel.pages[1].rotationDegrees, 0);
  });

  test('duplicate inserts a copy with a new pageId right after the source', () {
    viewModel.duplicate('a');
    final ids = viewModel.pages.map((p) => p.pageId).toList();
    expect(ids, hasLength(3));
    expect(ids[0], 'a');
    expect(ids[1], isNot('a'));
    expect(viewModel.pages[1].imagePath, pageAPath);
  });

  test('delete removes a page and clears its split/extract markers', () {
    viewModel.toggleSplitAfter('a');
    viewModel.toggleSelectedForExtract('a');
    viewModel.delete('a');

    expect(viewModel.pages.map((p) => p.pageId).toList(), ['b']);
    expect(viewModel.splitAfterPageIds, isEmpty);
    expect(viewModel.selectedForExtract, isEmpty);
  });

  test('split markers survive a reorder', () {
    viewModel.toggleSplitAfter('a');
    viewModel.reorder(0, 2);
    expect(viewModel.splitAfterPageIds, {'a'});
  });

  test('mergeAppend adds an external PDF\'s pages to the end', () async {
    await viewModel.mergeAppend(
      const ExternalPdfPageSource('/tmp/does-not-matter.pdf'),
    );
    expect(
      viewModel.pages,
      hasLength(2 + 3),
    ); // FakePdfRasterizerProvider default page count
    expect(viewModel.pages.sublist(0, 2).map((p) => p.pageId), ['a', 'b']);
  });

  test('insertBefore splices imported pages in before the target', () async {
    await viewModel.insertBefore(
      'b',
      const ExternalPdfPageSource('/tmp/does-not-matter.pdf', pageIndices: [0]),
    );
    final ids = viewModel.pages.map((p) => p.pageId).toList();
    expect(ids, hasLength(3));
    expect(ids.last, 'b');
    expect(ids.first, 'a');
  });

  test(
    'replace swaps one page for imported pages at the same position',
    () async {
      await viewModel.replace(
        'a',
        const ExternalPdfPageSource(
          '/tmp/does-not-matter.pdf',
          pageIndices: [0],
        ),
      );
      final ids = viewModel.pages.map((p) => p.pageId).toList();
      expect(ids, hasLength(2));
      expect(ids.last, 'b');
      expect(viewModel.pages.first.pageId, isNot('a'));
    },
  );

  test(
    'exportWhole produces a completed job with all pages embedded',
    () async {
      await viewModel.exportWhole(title: 'Combined');

      expect(viewModel.job?.status, ExportJobStatus.completed);
      final bytes = await File(viewModel.job!.outputPath!).readAsBytes();
      expect(_pdfPageCount(bytes), greaterThanOrEqualTo(2));
    },
  );

  test('extractSelected embeds only the selected subset', () async {
    viewModel.toggleSelectedForExtract('a');
    await viewModel.extractSelected(title: 'Extract');

    expect(viewModel.job?.status, ExportJobStatus.completed);
    final bytes = await File(viewModel.job!.outputPath!).readAsBytes();
    expect(_pdfPageCount(bytes), 1);
  });

  test(
    'exportSplit with one marker produces two jobs and two valid files',
    () async {
      viewModel.toggleSplitAfter('a');
      await viewModel.exportSplit(titlePrefix: 'Part');

      expect(viewModel.splitJobs, hasLength(2));
      expect(
        viewModel.splitJobs!.every(
          (j) => j.status == ExportJobStatus.completed,
        ),
        isTrue,
      );
      for (final job in viewModel.splitJobs!) {
        final bytes = await File(job.outputPath!).readAsBytes();
        expect(_pdfPageCount(bytes), 1);
      }
    },
  );

  test(
    'resetExportState clears a failed result back to the composer',
    () async {
      await viewModel.exportWhole(title: 'Combined');
      expect(viewModel.job, isNotNull);

      viewModel.resetExportState();

      expect(viewModel.job, isNull);
      expect(viewModel.splitJobs, isNull);
      expect(viewModel.progress, isNull);
    },
  );

  test('dispose clears the working session\'s scratch storage', () async {
    await viewModel.mergeAppend(
      const ExternalPdfPageSource('/tmp/does-not-matter.pdf', pageIndices: [0]),
    );
    viewModel.dispose();
    await Future<void>.delayed(Duration.zero);

    expect(workingPaths.clearedSessions, isNotEmpty);
  });
}
