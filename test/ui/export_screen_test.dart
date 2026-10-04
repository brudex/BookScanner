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
import 'package:bookscanner/l10n/gen/app_localizations.dart';
import 'package:bookscanner/ui/features/export/view_models/export_view_model.dart';
import 'package:bookscanner/ui/features/export/views/export_screen.dart';
import 'package:bookscanner/ui/features/page_review/views/export_convert_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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
    final controller = _controllers.putIfAbsent(
      job.id,
      () => StreamController.broadcast(),
    );
    controller.add(job);
    // Close once terminal: an indefinitely-open StreamSubscription (as
    // `ExportViewModel.startExport` creates via `watchJob(...).listen(...)`)
    // keeps `tester.runAsync`'s zone from ever appearing idle, hanging the
    // widget test forever -- a real fake-vs-production mismatch, since a
    // real repository's underlying data source doesn't have this problem
    // the same way an unclosed broadcast controller does in a test.
    const terminalStatuses = {
      ExportJobStatus.completed,
      ExportJobStatus.failed,
      ExportJobStatus.cancelled,
    };
    if (terminalStatuses.contains(job.status)) {
      await controller.close();
    }
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

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

void main() {
  late Directory tmpDir;
  late _FakePageRepository pageRepository;
  late _FakeProjectRepository projectRepository;
  late _FakeExportJobRepository exportJobRepository;
  late ExportProjectUseCase exportProjectUseCase;
  late ExportImagesUseCase exportImagesUseCase;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('export_screen_test_');
    final image = img.Image(width: 200, height: 300);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    final imagePath = p.join(tmpDir.path, 'page1.jpg');
    await File(imagePath).writeAsBytes(img.encodeJpg(image));

    pageRepository = _FakePageRepository();
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

    exportJobRepository = _FakeExportJobRepository();
    exportProjectUseCase = ExportProjectUseCase(
      pageRepository: pageRepository,
      ocrRepository: _FakeOcrRepository(),
      exportJobRepository: exportJobRepository,
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
    exportJobRepository: exportJobRepository,
    exportProjectUseCase: exportProjectUseCase,
    settingsRepository: _FakeSettingsRepository(),
    exportImagesUseCase: exportImagesUseCase,
  );

  testWidgets(
    'opened without a format, shows the Export / Convert sheet (with Word) '
    'instead of the old options form',
    (tester) async {
      final viewModel = buildViewModel();
      await tester.pumpWidget(
        _wrap(ExportScreen(projectId: 'proj1', viewModel: viewModel)),
      );
      // The progress bar behind the sheet animates, so pump for the sheet's
      // entrance instead of waiting to settle.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byKey(const ValueKey('reviewExportPdf')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('reviewExportMarkdown')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('reviewExportEpub')), findsOneWidget);
      expect(find.byKey(const ValueKey('reviewExportWord')), findsOneWidget);
      // The old form is gone.
      expect(find.byKey(const ValueKey('pdfOptionsPanel')), findsNothing);
      expect(find.byKey(const ValueKey('exportFormatDocx')), findsNothing);
    },
  );

  testWidgets('choosing Word on the sheet produces a Word launch', (
    tester,
  ) async {
    ExportLaunch? chosen;
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                chosen = await showExportConvertSheet(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reviewExportWord')));
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const ValueKey('reviewExportConfirm')),
    );
    await tester.tap(find.byKey(const ValueKey('reviewExportConfirm')));
    await tester.pumpAndSettle();

    expect(chosen?.format, ExportFormat.docx);
  });

  testWidgets('PDF starts with Recognize text off (image-only PDF)', (
    tester,
  ) async {
    ExportLaunch? chosen;
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                chosen = await showExportConvertSheet(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final ocr = tester.widget<Switch>(
      find.descendant(
        of: find.byKey(const ValueKey('reviewExportOcrSwitch')),
        matching: find.byType(Switch),
      ),
    );
    expect(ocr.value, isFalse);

    await tester.ensureVisible(
      find.byKey(const ValueKey('reviewExportConfirm')),
    );
    await tester.tap(find.byKey(const ValueKey('reviewExportConfirm')));
    await tester.pumpAndSettle();

    expect(chosen?.format, ExportFormat.imagePdf);
    expect(chosen?.pdfOptions?.searchable, isFalse);
  });

  testWidgets('launched with a format, shows progress straight away', (
    tester,
  ) async {
    final viewModel = buildViewModel();
    await tester.pumpWidget(
      _wrap(
        ExportScreen(
          projectId: 'proj1',
          viewModel: viewModel,
          launch: const ExportLaunch(format: ExportFormat.markdown),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('exportProgressBar')), findsOneWidget);
    expect(find.byKey(const ValueKey('reviewExportPdf')), findsNothing);
    expect(find.byKey(const ValueKey('pdfOptionsPanel')), findsNothing);
  });

  testWidgets(
    'shows the compose/edit-pages action for entering the page-composition screen',
    (tester) async {
      final viewModel = buildViewModel();
      await tester.pumpWidget(
        _wrap(ExportScreen(projectId: 'proj1', viewModel: viewModel)),
      );
      await tester.pump();

      // Not tap-tested here: tapping it calls `context.push(...)`, which needs
      // a real GoRouter ancestor that this screen's other tests don't set up
      // (no existing widget test in this codebase wraps with one -- that kind
      // of cross-screen navigation is covered by `integration_test/` instead).
      expect(find.byKey(const ValueKey('exportComposeButton')), findsOneWidget);
    },
  );

  // The completed/failed-state rendering (real PDF export success, and the
  // failure/retry path) is covered by plain `test()`s against
  // `ExportViewModel` directly in `export_view_model_test.dart` instead of
  // here: driving a real `dart:io`-based export through a pumped widget
  // tree hit a genuine `flutter_test` infrastructure gotcha (see that
  // file's doc comment) that cost a lot of session time to track down and
  // isn't worth fighting just to additionally prove the `Scaffold` renders
  // the right child -- that part is exercised by the format-picker test
  // above and by `_CompletedView`/`_FailedView` being trivial `Text`/`Icon`
  // widgets keyed directly off `ExportJobStatus`.
}
