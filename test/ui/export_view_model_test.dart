import 'dart:async';
import 'dart:io';

import 'package:bookscanner/data/services/export/dart_document_export_provider.dart';
import 'package:bookscanner/domain/models/export_job.dart';
import 'package:bookscanner/domain/models/ocr_block.dart';
import 'package:bookscanner/domain/models/project.dart';
import 'package:bookscanner/domain/models/scan_page.dart';
import 'package:bookscanner/domain/repositories/export_job_repository.dart';
import 'package:bookscanner/domain/repositories/ocr_repository.dart';
import 'package:bookscanner/domain/repositories/page_path_allocator.dart';
import 'package:bookscanner/domain/repositories/page_repository.dart';
import 'package:bookscanner/domain/repositories/project_repository.dart';
import 'package:bookscanner/domain/repositories/settings_repository.dart';
import 'package:bookscanner/domain/use_cases/export_images_use_case.dart';
import 'package:bookscanner/domain/use_cases/export_project_use_case.dart';
import 'package:bookscanner/ui/features/export/view_models/export_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

// Covers `ExportViewModel`'s real async export path (success and failure)
// with plain `test()`s rather than `testWidgets()`. This is deliberate:
// driving the same real `dart:io`-based export (genuine file reads/writes,
// real PDF encoding) through a *pumped widget tree* hit a `flutter_test`
// infrastructure gotcha that cost a lot of time to track down -- Flutter's
// fake-async test zone never considers itself idle while a live
// `StreamSubscription` (here, `ExportViewModel.startExport`'s
// `watchJob(...).listen(...)`) is open inside a `tester.runAsync()` block,
// so the test hung for the full default timeout (~10 minutes) twice before
// this was understood. A plain `test()` body runs on the real event loop
// with no fake clock and no such zone-idle detection, so none of that
// applies -- it is the correct tool for testing a real-I/O-driving
// ChangeNotifier's async behavior, leaving `testWidgets()` for what it's
// actually needed for (verifying the `Scaffold` renders the right child).

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

class _FakeSettingsRepository implements SettingsRepository {
  AppSettings _settings = const AppSettings();

  @override
  Future<AppSettings> getSettings() async => _settings;

  @override
  Future<void> updateSettings(AppSettings settings) async {
    _settings = settings;
  }

  @override
  Stream<AppSettings> watchSettings() => Stream.value(_settings);
}

class _FakeExportJobRepository implements ExportJobRepository {
  final _jobs = <String, ExportJob>{};
  final _controllers = <String, StreamController<ExportJob?>>{};

  @override
  Future<ExportJob> createJob(ExportJob job) async {
    _jobs[job.id] = job;
    _controllers
        .putIfAbsent(job.id, () => StreamController.broadcast())
        .add(job);
    return job;
  }

  @override
  Future<void> updateJob(ExportJob job) async {
    _jobs[job.id] = job;
    _controllers
        .putIfAbsent(job.id, () => StreamController.broadcast())
        .add(job);
  }

  @override
  Future<void> cancelJob(String jobId) async {}

  @override
  Stream<ExportJob?> watchJob(String jobId) => _controllers
      .putIfAbsent(jobId, () => StreamController.broadcast())
      .stream;

  @override
  Stream<List<ExportJob>> watchJobsForProject(String projectId) =>
      const Stream.empty();
}

class _FakeProjectRepository implements ProjectRepository {
  Project? nextProject;

  @override
  Future<Project?> getProject(String id) async => nextProject;

  @override
  Future<Set<String>> projectIdsMatchingOcrText(String text) async => {};

  @override
  Stream<Project?> watchProject(String id) => Stream.value(nextProject);

  @override
  Stream<List<Project>> watchProjects(ProjectQuery query) =>
      const Stream.empty();

  @override
  Future<Project> createProject({
    required ProjectType type,
    required String title,
  }) => throw UnimplementedError();

  @override
  Future<void> updateProject(Project project) async {}

  @override
  Future<void> moveToTrash(String id) async {}

  @override
  Future<void> restoreFromTrash(String id) async {}

  @override
  Future<void> deletePermanently(String id) async {}

  @override
  Future<void> renameProject(String id, String title) async {}
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
  late _FakeProjectRepository projectRepository;
  late ExportProjectUseCase exportProjectUseCase;
  late ExportImagesUseCase exportImagesUseCase;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('export_vm_test_');
    pageRepository = _FakePageRepository();
    projectRepository = _FakeProjectRepository();
    projectRepository.nextProject = Project(
      id: 'proj1',
      type: ProjectType.document,
      title: 'Test Project',
      metadata: const ProjectMetadata(),
      pageOrder: const ['p1'],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      processingState: ProcessingState.idle,
    );
    exportProjectUseCase = ExportProjectUseCase(
      pageRepository: pageRepository,
      ocrRepository: _FakeOcrRepository(),
      exportJobRepository: _FakeExportJobRepository(),
      exportProvider: DartDocumentExportProvider(),
      paths: _FakePaths(tmpDir),
    );
    exportImagesUseCase = ExportImagesUseCase(
      pageRepository: pageRepository,
      ocrRepository: _FakeOcrRepository(),
      exportProvider: DartDocumentExportProvider(),
      paths: _FakePaths(tmpDir),
    );
  });

  tearDown(() async {
    if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
  });

  ExportViewModel buildViewModel() => ExportViewModel(
    projectId: 'proj1',
    projectRepository: projectRepository,
    exportJobRepository: _FakeExportJobRepository(),
    exportProjectUseCase: exportProjectUseCase,
    settingsRepository: _FakeSettingsRepository(),
    exportImagesUseCase: exportImagesUseCase,
  );

  test(
    'a real image-only PDF export completes with a valid output file',
    () async {
      final image = img.Image(width: 200, height: 300);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));
      final imagePath = p.join(tmpDir.path, 'page1.jpg');
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

      final viewModel = buildViewModel();
      await viewModel.initialize();
      await viewModel.startExport(ExportFormat.imagePdf);

      expect(viewModel.error, isNull);
      expect(viewModel.job?.status, ExportJobStatus.completed);
      final outputPath = viewModel.job?.outputPath;
      expect(outputPath, isNotNull);
      expect(File(outputPath!).existsSync(), isTrue);
      final bytes = await File(outputPath).readAsBytes();
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    },
  );

  test(
    'a failing export (missing page image) surfaces a failed job, not a thrown exception',
    () async {
      await pageRepository.addPage(
        ScanPage(
          id: 'p1',
          projectId: 'proj1',
          sequence: 0,
          originalImagePath: p.join(tmpDir.path, 'does-not-exist.jpg'),
          processedImagePath: p.join(tmpDir.path, 'does-not-exist.jpg'),
          status: PageStatus.ready,
        ),
      );

      final viewModel = buildViewModel();
      await viewModel.initialize();
      await viewModel.startExport(ExportFormat.imagePdf);

      expect(viewModel.job?.status, ExportJobStatus.failed);
    },
  );
}
