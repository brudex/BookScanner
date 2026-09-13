import 'dart:io';

import 'package:bookscanner/data/services/scanner/adapters/dart_book_dewarp_provider.dart';
import 'package:bookscanner/data/services/local/app_paths.dart';
import 'package:bookscanner/data/services/local/file_storage_service.dart';
import 'package:bookscanner/domain/models/capture_models.dart';
import 'package:bookscanner/domain/models/geometry.dart';
import 'package:bookscanner/domain/models/project.dart';
import 'package:bookscanner/domain/models/provider_info.dart';
import 'package:bookscanner/domain/models/scan_page.dart';
import 'package:bookscanner/domain/providers/image_enhancement_provider.dart';
import 'package:bookscanner/domain/providers/page_detection_provider.dart';
import 'package:bookscanner/domain/repositories/page_repository.dart';
import 'package:bookscanner/domain/repositories/project_repository.dart';
import 'package:bookscanner/domain/use_cases/process_book_spread_use_case.dart';
import 'package:bookscanner/l10n/gen/app_localizations.dart';
import 'package:bookscanner/ui/features/page_review/view_models/spread_split_view_model.dart';
import 'package:bookscanner/ui/features/page_review/views/spread_split_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../data/fakes/fake_path_provider_platform.dart';

class _FakePageRepository implements PageRepository {
  final _pages = <String, ScanPage>{};

  @override
  Future<ScanPage?> getPage(String pageId) async => _pages[pageId];

  @override
  Future<void> addPage(ScanPage page) async => _pages[page.id] = page;

  @override
  Future<void> updatePage(ScanPage page) async => _pages[page.id] = page;

  @override
  Future<List<ScanPage>> getPages(String projectId) async =>
      _pages.values.where((p) => p.projectId == projectId).toList();

  @override
  Future<void> deletePage(String pageId) async {}

  @override
  Future<void> duplicatePage(String pageId) async {}

  @override
  Future<void> reorderPages(String projectId, List<String> order) async {}

  @override
  Stream<List<ScanPage>> watchPages(String projectId) => const Stream.empty();
}

class _FakeProjectRepository implements ProjectRepository {
  Project? nextProject;

  @override
  Future<Project?> getProject(String id) async => nextProject;

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

class _FakeDetectionProvider implements PageDetectionProvider {
  @override
  ProviderInfo get info =>
      const ProviderInfo(providerName: 'fake', adapterVersion: '1');

  @override
  Future<Quad?> detectQuad(String imagePath) async => null;
}

class _FakeEnhancementProvider implements ImageEnhancementProvider {
  @override
  ProviderInfo get info =>
      const ProviderInfo(providerName: 'fake', adapterVersion: '1');

  @override
  Future<double> scoreQuality(String imagePath) async => 0.9;

  @override
  Future<EnhancementResult> enhance(EnhancementRequest request) async {
    await File(request.sourceImagePath).copy(request.outputImagePath);
    return EnhancementResult(
      processedImagePath: request.outputImagePath,
      thumbnailPath: request.outputImagePath,
      qualityScore: 0.9,
      providerInfo: info,
    );
  }
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
  late _FakeProjectRepository projectRepository;
  late ProcessBookSpreadUseCase useCase;

  setUpAll(() async {
    tmpDir = await Directory.systemTemp.createTemp('spread_split_screen_test_');
    PathProviderPlatform.instance = FakePathProviderPlatform(tmpDir);
    paths = await AppPaths.instance();
  });

  tearDownAll(() async {
    if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
  });

  setUp(() async {
    pageRepository = _FakePageRepository();
    projectRepository = _FakeProjectRepository();
    useCase = ProcessBookSpreadUseCase(
      pageRepository: pageRepository,
      dewarpProvider: DartBookDewarpProvider(FileStorageService(paths)),
      detectionProvider: _FakeDetectionProvider(),
      enhancementProvider: _FakeEnhancementProvider(),
      fileStorage: paths,
    );

    projectRepository.nextProject = Project(
      id: 'proj1',
      type: ProjectType.book,
      title: 'Book',
      metadata: const ProjectMetadata(),
      pageOrder: const ['left1', 'right1'],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      processingState: ProcessingState.idle,
    );

    // Build a real spread + two split halves via the actual use case so the
    // screen has genuine files/state to load, mirroring how this feature is
    // actually exercised end-to-end rather than hand-faking view-model state.
    final spreadImage = img.Image(width: 400, height: 300);
    img.fill(spreadImage, color: img.ColorRgb8(255, 255, 255));
    final spreadPath = p.join(tmpDir.path, 'raw_spread.jpg');
    File(spreadPath).writeAsBytesSync(img.encodeJpg(spreadImage));

    await useCase.processCapture(
      capture: StillCapture(
        originalImagePath: spreadPath,
        detectedQuad: null,
        qualityScore: 0.9,
        warnings: const {},
        capturedAtMs: 0,
        providerInfo: const ProviderInfo(
          providerName: 'fake-capture',
          adapterVersion: '1',
        ),
      ),
      projectId: 'proj1',
      sequence: 0,
    );
  });

  test('setup produces two sibling pages', () async {
    final pages = await pageRepository.getPages('proj1');
    expect(pages, hasLength(2));
    expect(pages[0].spreadSiblingPageId, pages[1].id);
  });

  testWidgets('shows the spread image with a draggable split handle', (
    tester,
  ) async {
    final pages = await pageRepository.getPages('proj1');
    final viewModel = SpreadSplitViewModel(
      pageId: pages[0].id,
      pageRepository: pageRepository,
      projectRepository: projectRepository,
      processBookSpreadUseCase: useCase,
      paths: paths,
    );

    await tester.pumpWidget(
      _wrap(
        SpreadSplitScreen(
          projectId: 'proj1',
          pageId: pages[0].id,
          viewModel: viewModel,
        ),
      ),
    );
    await tester.runAsync(() => viewModel.initialize());
    await tester.pump();

    expect(find.byKey(const ValueKey('spreadSplitHandle')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('spreadSplitApplyButton')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('spreadSplitCancelButton')),
      findsOneWidget,
    );
  });

  testWidgets('dragging the handle moves the gutter position', (tester) async {
    final pages = await pageRepository.getPages('proj1');
    final viewModel = SpreadSplitViewModel(
      pageId: pages[0].id,
      pageRepository: pageRepository,
      projectRepository: projectRepository,
      processBookSpreadUseCase: useCase,
      paths: paths,
    );

    await tester.pumpWidget(
      _wrap(
        SpreadSplitScreen(
          projectId: 'proj1',
          pageId: pages[0].id,
          viewModel: viewModel,
        ),
      ),
    );
    await tester.runAsync(() => viewModel.initialize());
    await tester.pump();

    final before = viewModel.gutterX;
    viewModel.dragGutter(0.1);
    expect(viewModel.gutterX, closeTo(before + 0.1, 1e-9));
  });
}
