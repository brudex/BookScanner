import 'dart:io';

import 'package:bookscanner/data/services/export/adapters/fake_pdf_rasterizer_provider.dart';
import 'package:bookscanner/data/services/export/dart_document_export_provider.dart';
import 'package:bookscanner/data/services/local/app_paths.dart';
import 'package:bookscanner/data/services/local/app_working_session_paths.dart';
import 'package:bookscanner/domain/models/ocr_block.dart';
import 'package:bookscanner/domain/models/scan_page.dart';
import 'package:bookscanner/domain/repositories/export_job_repository.dart';
import 'package:bookscanner/domain/repositories/ocr_repository.dart';
import 'package:bookscanner/domain/repositories/page_repository.dart';
import 'package:bookscanner/domain/use_cases/export_page_inputs_use_case.dart';
import 'package:bookscanner/domain/use_cases/load_page_source_use_case.dart';
import 'package:bookscanner/domain/use_cases/load_project_page_inputs_use_case.dart';
import 'package:bookscanner/domain/models/export_job.dart';
import 'package:bookscanner/l10n/gen/app_localizations.dart';
import 'package:bookscanner/ui/features/page_operations/view_models/page_operations_view_model.dart';
import 'package:bookscanner/ui/features/page_operations/views/page_operations_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../data/fakes/fake_path_provider_platform.dart';

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
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmpDir;
  late AppPaths paths;
  late _FakePageRepository pageRepository;

  setUpAll(() async {
    tmpDir = await Directory.systemTemp.createTemp(
      'page_operations_screen_test_',
    );
    PathProviderPlatform.instance = FakePathProviderPlatform(tmpDir);
    paths = await AppPaths.instance();
  });

  tearDownAll(() async {
    if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
  });

  setUp(() async {
    pageRepository = _FakePageRepository();

    final image = img.Image(width: 100, height: 150);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    final imagePath = p.join(tmpDir.path, 'page-a.jpg');
    await File(imagePath).writeAsBytes(img.encodeJpg(image));

    await pageRepository.addPage(
      ScanPage(
        id: 'a',
        projectId: 'proj1',
        sequence: 0,
        originalImagePath: imagePath,
        status: PageStatus.ready,
      ),
    );
    await pageRepository.addPage(
      ScanPage(
        id: 'b',
        projectId: 'proj1',
        sequence: 1,
        originalImagePath: imagePath,
        status: PageStatus.ready,
      ),
    );
  });

  PageOperationsViewModel buildViewModel() {
    final projectLoader = LoadProjectPageInputsUseCase(
      pageRepository: pageRepository,
      ocrRepository: _FakeOcrRepository(),
    );
    final workingPaths = AppWorkingSessionPaths(paths);
    return PageOperationsViewModel(
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
        paths: paths,
      ),
      workingPaths: workingPaths,
      rasterizer: FakePdfRasterizerProvider(),
    );
  }

  testWidgets('shows both pages in a reorderable list once loaded', (
    tester,
  ) async {
    final viewModel = buildViewModel();
    await tester.pumpWidget(
      _wrap(PageOperationsScreen(projectId: 'proj1', viewModel: viewModel)),
    );
    await tester.runAsync(() => viewModel.initialize());
    await tester.pump();

    expect(find.byKey(const ValueKey('pageOperationsList')), findsOneWidget);
    expect(find.byKey(const ValueKey('page-a')), findsOneWidget);
    expect(find.byKey(const ValueKey('page-b')), findsOneWidget);
    expect(find.byKey(const ValueKey('composeExportButton')), findsOneWidget);
  });

  testWidgets('rotate menu action rotates just that page', (tester) async {
    final viewModel = buildViewModel();
    await tester.pumpWidget(
      _wrap(PageOperationsScreen(projectId: 'proj1', viewModel: viewModel)),
    );
    await tester.runAsync(() => viewModel.initialize());
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('composeMenu-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rotate').last);
    await tester.pump();

    expect(
      viewModel.pages.firstWhere((p) => p.pageId == 'a').rotationDegrees,
      90,
    );
    expect(
      viewModel.pages.firstWhere((p) => p.pageId == 'b').rotationDegrees,
      0,
    );
  });

  testWidgets('duplicate menu action adds a copy to the list', (tester) async {
    final viewModel = buildViewModel();
    await tester.pumpWidget(
      _wrap(PageOperationsScreen(projectId: 'proj1', viewModel: viewModel)),
    );
    await tester.runAsync(() => viewModel.initialize());
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('composeMenu-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicate').last);
    await tester.pump();

    expect(viewModel.pages, hasLength(3));
  });

  testWidgets('delete menu action removes that page', (tester) async {
    final viewModel = buildViewModel();
    await tester.pumpWidget(
      _wrap(PageOperationsScreen(projectId: 'proj1', viewModel: viewModel)),
    );
    await tester.runAsync(() => viewModel.initialize());
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('composeMenu-b')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pump();

    expect(viewModel.pages.map((p) => p.pageId), ['a']);
    expect(find.byKey(const ValueKey('page-b')), findsNothing);
  });

  testWidgets('split-after toggle shows a divider marker beneath the page', (
    tester,
  ) async {
    final viewModel = buildViewModel();
    await tester.pumpWidget(
      _wrap(PageOperationsScreen(projectId: 'proj1', viewModel: viewModel)),
    );
    await tester.runAsync(() => viewModel.initialize());
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('composeMenu-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Split after this page').last);
    await tester.pump();

    expect(viewModel.splitAfterPageIds, {'a'});
    expect(find.byType(Divider), findsOneWidget);
  });

  testWidgets(
    'select-for-extract mode shows checkboxes and hides the popup menu',
    (tester) async {
      final viewModel = buildViewModel();
      await tester.pumpWidget(
        _wrap(PageOperationsScreen(projectId: 'proj1', viewModel: viewModel)),
      );
      await tester.runAsync(() => viewModel.initialize());
      await tester.pump();

      await tester.tap(
        find.byKey(const ValueKey('composeSelectForExtractButton')),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('composeSelectCheckbox-a')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('composeMenu-a')), findsNothing);
      expect(find.byKey(const ValueKey('composeExportButton')), findsNothing);
    },
  );

  testWidgets('exporting the whole document shows the completed result', (
    tester,
  ) async {
    final viewModel = buildViewModel();
    await tester.pumpWidget(
      _wrap(PageOperationsScreen(projectId: 'proj1', viewModel: viewModel)),
    );
    await tester.runAsync(() => viewModel.initialize());
    await tester.pump();

    await tester.runAsync(() => viewModel.exportWhole(title: 'Combined'));
    await tester.pump();

    expect(find.byKey(const ValueKey('exportCompleteMessage')), findsOneWidget);
  });

  testWidgets(
    'exporting with a split marker shows the multi-file results view',
    (tester) async {
      final viewModel = buildViewModel();
      await tester.pumpWidget(
        _wrap(PageOperationsScreen(projectId: 'proj1', viewModel: viewModel)),
      );
      await tester.runAsync(() => viewModel.initialize());
      await tester.pump();
      viewModel.toggleSplitAfter('a');

      await tester.runAsync(() => viewModel.exportSplit(titlePrefix: 'Part'));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('composeSplitResultsList')),
        findsOneWidget,
      );
    },
  );
}
