import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:bookscanner/data/services/local/app_paths.dart';
import 'package:bookscanner/data/services/scanner/adapters/dart_book_dewarp_provider.dart';
import 'package:bookscanner/data/services/local/file_storage_service.dart';
import 'package:bookscanner/domain/models/capture_models.dart';
import 'package:bookscanner/domain/models/geometry.dart';
import 'package:bookscanner/domain/models/project.dart';
import 'package:bookscanner/domain/models/provider_info.dart';
import 'package:bookscanner/domain/models/scan_page.dart';
import 'package:bookscanner/domain/providers/capture_provider.dart';
import 'package:bookscanner/domain/providers/image_enhancement_provider.dart';
import 'package:bookscanner/domain/providers/page_detection_provider.dart';
import 'package:bookscanner/domain/repositories/page_repository.dart';
import 'package:bookscanner/domain/repositories/project_repository.dart';
import 'package:bookscanner/domain/use_cases/capture_page_use_case.dart';
import 'package:bookscanner/domain/use_cases/process_book_spread_use_case.dart';
import 'package:bookscanner/l10n/gen/app_localizations.dart';
import 'package:bookscanner/ui/features/capture/view_models/capture_view_model.dart';
import 'package:bookscanner/ui/features/capture/views/capture_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';

import '../data/fakes/fake_path_provider_platform.dart';
import '../data/fakes/fake_permission_handler_platform.dart';

/// A capture provider double built specifically for widget tests: unlike
/// `FakeCaptureProvider` (used by contract/integration tests), this one
/// never starts a `Timer.periodic` or emits synthetic analysis frames. A
/// live periodic timer created inside `flutter_test`'s fake-async test zone
/// during `initState()` cannot be reliably cancelled again from within the
/// same zone via a plain `await` -- attempting that (`await
/// viewModel.closeSession()` directly in a test body) hung for minutes
/// rather than completing, which is what motivated this simpler double:
/// with no timer and no live subscription ever created, there is nothing
/// to leak or race, and `CaptureScreen`'s auto-capture behavior (which
/// depends on repeated analysis frames) is simply out of scope for these
/// tests.
class _TestCaptureProvider implements CaptureProvider {
  int _captureCount = 0;
  bool _sessionOpen = false;
  final Directory _tmpDir;

  /// When set, `openSession()` waits on this before completing -- lets a
  /// test observe the in-between state where permission is granted but the
  /// session has not actually opened yet.
  Completer<void>? openGate;

  /// Tests that need to push a [FrameAnalysis] (e.g. the live quad overlay)
  /// set this before pumping; left null everywhere else so
  /// `analysisStream()` stays a no-op empty stream, matching every other
  /// test in this file (see the class doc comment on why no real timer/
  /// subscription is ever created by default).
  StreamController<FrameAnalysis>? analysisController;

  /// When set, `captureStill()` waits on this before resolving -- lets a
  /// test dispose the view model while a capture is still in flight.
  Completer<void>? captureGate;

  _TestCaptureProvider(this._tmpDir);

  @override
  int? get previewTextureId => null;

  @override
  double get previewAspectRatio => 4 / 3;

  @override
  ProviderInfo get info => const ProviderInfo(
    providerName: 'test-capture',
    adapterVersion: '1.0.0-test',
  );

  @override
  Future<ScannerCapabilities> capabilities() async => const ScannerCapabilities(
    liveEdgeDetection: true,
    offlineOcr: true,
    handwritingOcr: false,
    bookDewarping: true,
    fingerRemoval: false,
    supportedOcrLanguages: {'en'},
    torch: true,
    opticalZoom: true,
  );

  @override
  Future<void> openSession(CaptureMode mode) async {
    if (openGate != null) await openGate!.future;
    _sessionOpen = true;
  }

  @override
  Stream<FrameAnalysis> analysisStream() =>
      analysisController?.stream ?? const Stream.empty();

  @override
  Future<StillCapture> captureStill({bool bypassQualityGate = false}) async {
    if (captureGate != null) await captureGate!.future;
    if (!_sessionOpen) {
      throw const ProviderException(
        ProviderErrorCategory.processingFailed,
        'Session not open',
      );
    }
    _captureCount += 1;
    final rand = Random(_captureCount);
    final image = img.Image(width: 1240, height: 1754);
    img.fill(image, color: img.ColorRgb8(250, 250, 248));
    for (var i = 0; i < 18; i++) {
      final y = 80 + i * 90;
      img.drawLine(
        image,
        x1: 60,
        y1: y,
        x2: 1180,
        y2: y,
        color: img.ColorRgb8(30 + rand.nextInt(20), 30, 30),
        thickness: 3,
      );
    }
    final path = p.join(_tmpDir.path, 'test_capture_$_captureCount.jpg');
    await File(path).writeAsBytes(img.encodeJpg(image, quality: 90));

    return StillCapture(
      originalImagePath: path,
      detectedQuad: Quad.fullFrame,
      qualityScore: 0.9,
      warnings: const {},
      capturedAtMs: DateTime.now().millisecondsSinceEpoch,
      providerInfo: info,
    );
  }

  @override
  Future<void> setFlashMode(FlashMode mode) async {}

  @override
  Future<void> setZoom(double level) async {}

  @override
  Future<void> setFocusAndExposurePoint(double x, double y) async {}

  @override
  Future<void> closeSession() async {
    _sessionOpen = false;
  }
}

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
  final renameCalls = <(String, String)>[];

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
  Future<void> renameProject(String id, String title) async {
    renameCalls.add((id, title));
  }
}

class _FakeDetectionProvider implements PageDetectionProvider {
  @override
  ProviderInfo get info =>
      const ProviderInfo(providerName: 'fake', adapterVersion: '1');

  @override
  Future<Quad?> detectQuad(String imagePath) async => null;
}

class _FakeEnhancementProvider implements ImageEnhancementProvider {
  /// When set, `enhance()` waits on this before resolving -- lets a test
  /// observe the in-between state where a page has been captured but not
  /// yet fully processed/added.
  Completer<void>? enhanceGate;

  @override
  ProviderInfo get info =>
      const ProviderInfo(providerName: 'fake', adapterVersion: '1');

  @override
  Future<double> scoreQuality(String imagePath) async => 0.9;

  @override
  Future<EnhancementResult> enhance(EnhancementRequest request) async {
    if (enhanceGate != null) await enhanceGate!.future;
    await File(request.sourceImagePath).copy(request.outputImagePath);
    return EnhancementResult(
      processedImagePath: request.outputImagePath,
      thumbnailPath: request.outputImagePath,
      qualityScore: 0.9,
      providerInfo: info,
      cropPoints: request.cropPoints,
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
  late _TestCaptureProvider captureProvider;
  late CapturePageUseCase capturePageUseCase;
  late ProcessBookSpreadUseCase processBookSpreadUseCase;
  late FakePermissionHandlerPlatform permissionPlatform;
  late _FakeEnhancementProvider enhancementProvider;

  setUpAll(() async {
    tmpDir = await Directory.systemTemp.createTemp('capture_screen_test_');
    PathProviderPlatform.instance = FakePathProviderPlatform(tmpDir);
    paths = await AppPaths.instance();
  });

  tearDownAll(() async {
    if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
  });

  setUp(() {
    pageRepository = _FakePageRepository();
    projectRepository = _FakeProjectRepository();
    projectRepository.nextProject = Project(
      id: 'proj1',
      type: ProjectType.document,
      title: 'Doc',
      metadata: const ProjectMetadata(),
      pageOrder: const [],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      processingState: ProcessingState.idle,
    );
    captureProvider = _TestCaptureProvider(tmpDir);
    enhancementProvider = _FakeEnhancementProvider();
    capturePageUseCase = CapturePageUseCase(
      pageRepository: pageRepository,
      enhancementProvider: enhancementProvider,
      detectionProvider: _FakeDetectionProvider(),
      fileStorage: paths,
    );
    processBookSpreadUseCase = ProcessBookSpreadUseCase(
      pageRepository: pageRepository,
      dewarpProvider: DartBookDewarpProvider(FileStorageService(paths)),
      detectionProvider: _FakeDetectionProvider(),
      enhancementProvider: _FakeEnhancementProvider(),
      fileStorage: paths,
    );
    permissionPlatform = FakePermissionHandlerPlatform();
    PermissionHandlerPlatform.instance = permissionPlatform;
  });

  CaptureViewModel buildViewModel({
    Duration resultPreviewHold = Duration.zero,
    String? replacePageId,
  }) => CaptureViewModel(
    projectId: 'proj1',
    captureProvider: captureProvider,
    capturePageUseCase: capturePageUseCase,
    processBookSpreadUseCase: processBookSpreadUseCase,
    projectRepository: projectRepository,
    pageRepository: pageRepository,
    replacePageId: replacePageId,
    resultPreviewHold: resultPreviewHold,
  );

  testWidgets(
    'shows the camera preview placeholder and shutter once permission is granted',
    (tester) async {
      final viewModel = buildViewModel();
      await tester.pumpWidget(
        _wrap(CaptureScreen(projectId: 'proj1', viewModel: viewModel)),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const ValueKey('shutterButton')), findsOneWidget);
      expect(find.byKey(const ValueKey('captureDoneButton')), findsOneWidget);
      expect(find.byKey(const ValueKey('capturePageCount')), findsOneWidget);
      expect(find.text('No pages yet'), findsOneWidget);
    },
  );

  testWidgets(
    'does not render a tappable shutter until the capture session is actually open',
    (tester) async {
      // Regression test: an on-device integration test run found that
      // `notifyListeners()` fires with `permissionState == granted` before
      // `_openSession()` is awaited in `CaptureViewModel.initialize()`,
      // which used to let `CaptureScreen` render a tappable shutter button
      // while `_sessionOpen` was still false. Tapping it then silently
      // no-oped (`captureManually`'s `!_sessionOpen` guard returns `const
      // []` with no error), losing the capture with no feedback to the
      // user. Held open here via `openGate` to freeze that in-between
      // state and assert on it directly.
      final gate = Completer<void>();
      captureProvider.openGate = gate;
      final viewModel = buildViewModel();
      await tester.pumpWidget(
        _wrap(CaptureScreen(projectId: 'proj1', viewModel: viewModel)),
      );
      await tester.pump();
      await tester.pump();

      expect(viewModel.permissionState, CapturePermissionState.granted);
      expect(viewModel.sessionOpen, isFalse);
      expect(find.byKey(const ValueKey('shutterButton')), findsNothing);
      expect(
        find.byKey(const ValueKey('captureSessionOpening')),
        findsOneWidget,
      );

      gate.complete();
      await tester.pump();
      await tester.pump();

      expect(viewModel.sessionOpen, isTrue);
      expect(find.byKey(const ValueKey('shutterButton')), findsOneWidget);
      expect(find.byKey(const ValueKey('captureSessionOpening')), findsNothing);
    },
  );

  testWidgets('shows the permission rationale when camera access is denied', (
    tester,
  ) async {
    permissionPlatform.statusToReturn = PermissionStatus.denied;
    final viewModel = buildViewModel();
    await tester.pumpWidget(
      _wrap(CaptureScreen(projectId: 'proj1', viewModel: viewModel)),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('shutterButton')), findsNothing);
    expect(
      find.byKey(const ValueKey('capturePermissionAction')),
      findsOneWidget,
    );
  });

  testWidgets('capturing a page updates the on-screen page count', (
    tester,
  ) async {
    final viewModel = buildViewModel();
    await tester.pumpWidget(
      _wrap(CaptureScreen(projectId: 'proj1', viewModel: viewModel)),
    );
    await tester.pump();
    await tester.pump();

    expect(viewModel.pageCount, 0);

    // Driven directly on the view model (rather than via `tester.tap`) and
    // wrapped in `runAsync`: `captureManually` performs real file I/O
    // through the test capture provider and use cases, which never
    // completes under the widget-test fake-async zone otherwise (see
    // export_view_model_test.dart for the fuller writeup of why real I/O
    // needs `runAsync` under `testWidgets`).
    await tester.runAsync(() => viewModel.captureManually());
    await tester.pump();

    expect(viewModel.pageCount, 1);
    expect(find.text('1 page scanned'), findsOneWidget);
    final pages = await pageRepository.getPages('proj1');
    expect(pages, hasLength(1));
  });

  // Exercised at the ViewModel level, not through a pumped CaptureScreen:
  // interleaving a still-in-flight `runAsync` future with widget pumps
  // (needed to observe the mid-processing state) isn't a supported
  // combination -- it hung rather than settling. A plain `test()` runs real
  // async normally, with no fake-async pump machinery to fight.
  test('freezes on the captured frame until the page is fully added, '
      'then clears and the page count reflects it', () async {
    final gate = Completer<void>();
    enhancementProvider.enhanceGate = gate;
    final viewModel = buildViewModel();
    await viewModel.initialize();

    expect(viewModel.pageCount, 0);
    expect(viewModel.frozenPreviewPath, isNull);

    final captureFuture = viewModel.captureManually();
    // Let captureStill() resolve (setting the frozen path) without
    // waiting for the gated enhancement step to complete too --
    // captureStill does real file I/O, so poll briefly rather than
    // assuming a single microtask turn is enough.
    for (var i = 0; i < 50 && viewModel.frozenPreviewPath == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(viewModel.frozenPreviewPath, isNotNull);
    expect(viewModel.capturing, isTrue);
    expect(viewModel.pageCount, 0);

    gate.complete();
    await captureFuture;

    expect(viewModel.frozenPreviewPath, isNull);
    expect(viewModel.pageCount, 1);
  });

  test(
    'marks capturing immediately on shutter, before captureStill returns',
    () async {
      final gate = Completer<void>();
      captureProvider.captureGate = gate;
      final viewModel = buildViewModel();
      await viewModel.initialize();

      final captureFuture = viewModel.captureManually();
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.capturing, isTrue);
      expect(viewModel.frozenPreviewPath, isNull);

      gate.complete();
      await captureFuture;
      expect(viewModel.capturing, isFalse);
    },
  );

  test(
    'after processing, holds the cropped result on screen before returning to the live camera',
    () async {
      final gate = Completer<void>();
      enhancementProvider.enhanceGate = gate;
      final viewModel = buildViewModel(
        resultPreviewHold: const Duration(milliseconds: 80),
      );
      await viewModel.initialize();

      final captureFuture = viewModel.captureManually();
      for (var i = 0; i < 50 && viewModel.frozenPreviewPath == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(viewModel.frozenPreviewPath, isNotNull);
      expect(viewModel.resultPreviewPath, isNull);

      gate.complete();
      for (var i = 0; i < 50 && viewModel.resultPreviewPath == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(viewModel.resultPreviewPath, isNotNull);
      expect(viewModel.frozenPreviewPath, isNull);
      expect(viewModel.pageCount, 1);
      expect(File(viewModel.resultPreviewPath!).existsSync(), isTrue);

      await captureFuture;
      expect(viewModel.resultPreviewPath, isNull);
    },
  );

  testWidgets(
    'shows a fixed capture frame guide as soon as the preview is up, regardless of analysis',
    (tester) async {
      captureProvider.analysisController = StreamController<FrameAnalysis>();
      addTearDown(() => captureProvider.analysisController!.close());
      final viewModel = buildViewModel();
      await tester.pumpWidget(
        _wrap(CaptureScreen(projectId: 'proj1', viewModel: viewModel)),
      );
      await tester.pump();
      await tester.pump();

      // Present immediately -- a static target the user aligns the document
      // to, not something that waits for (or tracks) a detected quad.
      expect(find.byKey(const ValueKey('captureFrameGuide')), findsOneWidget);

      captureProvider.analysisController!.add(
        const FrameAnalysis(
          timestampMs: 0,
          documentDetected: true,
          quad: Quad.fullFrame,
          cornersStable: true,
          motionBelowThreshold: true,
          focusAcceptable: true,
          exposureAcceptable: true,
          warnings: {},
        ),
      );
      await tester.pump();
      await tester.pump();

      // Still just the one guide once a stable analysis frame arrives --
      // only its color reacts, never its position or count.
      expect(find.byKey(const ValueKey('captureFrameGuide')), findsOneWidget);
    },
  );

  // Regression test: capture used to auto-fire once a frame held every
  // quality gate for a ~600ms stable window (SPEC 17.3). Rejected on-device
  // -- the shutter showed the same spinner an auto-fired capture used as a
  // manual one, so it visibly locked out and spun on its own while the user
  // was still lining up the shot. Capture must now be manual-only.
  testWidgets(
    'stable analysis frames alone never trigger a capture -- only a manual shutter tap does',
    (tester) async {
      captureProvider.analysisController = StreamController<FrameAnalysis>();
      addTearDown(() => captureProvider.analysisController!.close());
      final viewModel = buildViewModel();
      await tester.pumpWidget(
        _wrap(CaptureScreen(projectId: 'proj1', viewModel: viewModel)),
      );
      await tester.pump();
      await tester.pump();

      const stableFrame = FrameAnalysis(
        timestampMs: 0,
        documentDetected: true,
        quad: Quad.fullFrame,
        cornersStable: true,
        motionBelowThreshold: true,
        focusAcceptable: true,
        exposureAcceptable: true,
        warnings: {},
      );
      // Several stable frames in a row -- the old logic fired after ~600ms
      // of exactly this.
      for (var i = 0; i < 5; i++) {
        captureProvider.analysisController!.add(stableFrame);
        await tester.pump();
      }
      await tester.pump(const Duration(seconds: 1));

      expect(viewModel.pageCount, 0);
      expect(viewModel.capturing, isFalse);
      final pages = await pageRepository.getPages('proj1');
      expect(pages, isEmpty);
    },
  );

  testWidgets(
    'tapping Done prompts to name the scan, defaulted to a timestamp',
    (tester) async {
      final viewModel = buildViewModel();
      await tester.pumpWidget(
        _wrap(CaptureScreen(projectId: 'proj1', viewModel: viewModel)),
      );
      await tester.pump();
      await tester.pump();

      // `onDone`'s `closeSession()` await never itself schedules a widget
      // rebuild, so `pumpAndSettle()` alone considers the tree "settled"
      // and returns before that microtask chain actually reaches
      // `showDialog` -- the same class of issue `captureManually` has
      // elsewhere in this file, needing `runAsync` for real async work to
      // actually complete under the default fake-async test zone.
      await tester.runAsync(
        () => tester.tap(find.byKey(const ValueKey('captureDoneButton'))),
      );
      await tester.pumpAndSettle();
      // Deliberately not tapping Save or Cancel: both proceed to a real
      // `context.pushReplacement`, which (like `context.pop()` elsewhere in
      // this file) needs a real GoRouter ancestor this harness doesn't set
      // up -- that part is covered by integration_test/ instead. This test
      // only covers the dialog itself.

      expect(find.byKey(const ValueKey('captureNameField')), findsOneWidget);
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('captureNameField')),
      );
      // "MM-dd HH:mm", e.g. "09-01 14:23" -- proves it defaults to a real
      // timestamp, not an empty or hard-coded field.
      expect(
        field.controller!.text,
        matches(RegExp(r'^\d{2}-\d{2} \d{2}:\d{2}$')),
      );
    },
  );

  test('renameProject delegates to the project repository', () async {
    final viewModel = buildViewModel();
    await viewModel.initialize();

    await viewModel.renameProject('My Trip Receipts');

    expect(projectRepository.renameCalls, [('proj1', 'My Trip Receipts')]);
  });

  // Regression test for a real on-device crash ("A CaptureViewModel was
  // used after being disposed"): the user backed out of the Capture screen
  // while a shutter tap was still processing, so `captureManually`'s
  // `finally` block called `notifyListeners()` after `dispose()` had
  // already run. Exercised at the ViewModel level -- no pumped widget
  // needed to reproduce a dispose-during-await race.
  test(
    'captureManually completing after the view model is disposed does not throw',
    () async {
      final gate = Completer<void>();
      captureProvider.captureGate = gate;
      final viewModel = buildViewModel();
      await viewModel.initialize();

      final captureFuture = viewModel.captureManually();
      viewModel.dispose();
      gate.complete();

      await expectLater(captureFuture, completes);
    },
  );

  // Deliberately exercised at the ViewModel level, not through a pumped
  // CaptureScreen: `_onViewModelChanged` calls `context.pop()` once
  // `replacementComplete` flips true, which needs a real GoRouter ancestor
  // that (matching every other screen test in this codebase -- see
  // export_screen_test.dart's compose-button test) isn't set up here. The
  // navigation-on-completion wiring itself is covered by
  // `integration_test/` instead; what's tested directly here is the
  // business logic: does a replace session actually replace in place.
  test(
    'a replacePageId session replaces that page in place instead of appending, '
    'and signals replacementComplete after exactly one capture',
    () async {
      final oldImagePath = p.join(tmpDir.path, 'old.jpg');
      await File(oldImagePath).writeAsBytes([1, 2, 3]);
      await pageRepository.addPage(
        ScanPage(
          id: 'existing-page',
          projectId: 'proj1',
          sequence: 0,
          originalImagePath: oldImagePath,
          status: PageStatus.needsRescan,
        ),
      );
      final viewModel = CaptureViewModel(
        projectId: 'proj1',
        captureProvider: captureProvider,
        capturePageUseCase: capturePageUseCase,
        processBookSpreadUseCase: processBookSpreadUseCase,
        projectRepository: projectRepository,
        pageRepository: pageRepository,
        replacePageId: 'existing-page',
      );
      await viewModel.initialize();
      // initialize() seeds pageCount from the project's existing pages
      // (just the one added above).
      expect(viewModel.pageCount, 1);
      expect(viewModel.replacementComplete, isFalse);

      await viewModel.captureManually();

      expect(viewModel.replacementComplete, isTrue);
      // Replaced in place, not appended as a new page.
      final pages = await pageRepository.getPages('proj1');
      expect(pages, hasLength(1));
      expect(pages.single.id, 'existing-page');
      expect(pages.single.status, PageStatus.ready);
      expect(pages.single.originalImagePath, isNot(oldImagePath));
      // pageCount (used for the *next new page's* sequence number) is
      // unaffected by a replace -- still just the 1 pre-existing page.
      expect(viewModel.pageCount, 1);
    },
  );

  test(
    'quality warnings block capture until bypassQualityGate is passed',
    () async {
      captureProvider.analysisController =
          StreamController<FrameAnalysis>.broadcast();
      addTearDown(() => captureProvider.analysisController!.close());
      final viewModel = buildViewModel();
      await viewModel.initialize();
      captureProvider.analysisController!.add(
        const FrameAnalysis(
          timestampMs: 1,
          documentDetected: false,
          quad: null,
          cornersStable: false,
          motionBelowThreshold: false,
          focusAcceptable: false,
          exposureAcceptable: false,
          warnings: {QualityWarning.blur},
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final blocked = await viewModel.captureManually();
      expect(blocked, isEmpty);
      expect(viewModel.awaitingQualityOverride, isTrue);
      expect(viewModel.pageCount, 0);

      final pages = await viewModel.captureManually(bypassQualityGate: true);
      expect(pages, isNotEmpty);
    },
  );

  testWidgets('a confident live quad draws the detected polygon overlay', (
    tester,
  ) async {
    captureProvider.analysisController = StreamController<FrameAnalysis>();
    addTearDown(() => captureProvider.analysisController!.close());
    final viewModel = buildViewModel();
    await tester.pumpWidget(
      _wrap(CaptureScreen(projectId: 'proj1', viewModel: viewModel)),
    );
    await tester.pump();
    await tester.pump();

    captureProvider.analysisController!.add(
      const FrameAnalysis(
        timestampMs: 0,
        documentDetected: true,
        quad: Quad(
          topLeft: Point2D(x: 0.2, y: 0.2),
          topRight: Point2D(x: 0.8, y: 0.2),
          bottomRight: Point2D(x: 0.8, y: 0.8),
          bottomLeft: Point2D(x: 0.2, y: 0.8),
        ),
        cornersStable: true,
        motionBelowThreshold: true,
        focusAcceptable: true,
        exposureAcceptable: true,
        warnings: {},
        confidence: 0.8,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('captureDetectedPolygon')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('captureFlashButton')), findsOneWidget);
    expect(find.byKey(const ValueKey('captureZoomSlider')), findsOneWidget);
  });
}
