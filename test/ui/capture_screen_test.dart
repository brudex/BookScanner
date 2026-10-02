import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:bookscanner/data/services/local/app_paths.dart';
import 'package:bookscanner/domain/models/capture_models.dart';
import 'package:bookscanner/domain/models/geometry.dart';
import 'package:bookscanner/domain/models/project.dart';
import 'package:bookscanner/domain/models/provider_info.dart';
import 'package:bookscanner/domain/models/scan_page.dart';
import 'package:bookscanner/domain/providers/book_dewarp_provider.dart';
import 'package:bookscanner/domain/providers/capture_provider.dart';
import 'package:bookscanner/domain/providers/image_enhancement_provider.dart';
import 'package:bookscanner/domain/providers/page_detection_provider.dart';
import 'package:bookscanner/domain/repositories/page_repository.dart';
import 'package:bookscanner/domain/repositories/project_repository.dart';
import 'package:bookscanner/domain/repositories/settings_repository.dart';
import 'package:bookscanner/domain/use_cases/capture_page_use_case.dart';
import 'package:bookscanner/domain/use_cases/process_book_spread_use_case.dart';
import 'package:bookscanner/l10n/gen/app_localizations.dart';
import 'package:bookscanner/routing/app_router.dart';
import 'package:bookscanner/ui/features/capture/view_models/capture_view_model.dart';
import 'package:bookscanner/ui/features/capture/views/capture_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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
  Future<void> renameProject(String id, String title) async {
    renameCalls.add((id, title));
  }
}

class _FakeSettingsRepository implements SettingsRepository {
  _FakeSettingsRepository({AppSettings? settings})
    : _settings = settings ?? const AppSettings();

  AppSettings _settings;

  @override
  Future<AppSettings> getSettings() async => _settings;

  @override
  Future<void> updateSettings(AppSettings settings) async {
    _settings = settings;
  }

  @override
  Stream<AppSettings> watchSettings() => Stream.value(_settings);
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

class _FakeBookDewarpProvider implements BookDewarpProvider {
  _FakeBookDewarpProvider(this._tmpDir);

  final Directory _tmpDir;
  int splitCalls = 0;
  int dewarpCalls = 0;

  @override
  ProviderInfo get info =>
      const ProviderInfo(providerName: 'fake-book-dewarp', adapterVersion: '1');

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<SpreadSplitResult> splitSpread(
    String spreadImagePath, {
    double? gutterXOverride,
  }) async {
    splitCalls++;
    final image = img.Image(width: 40, height: 60);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    final leftPath = p.join(_tmpDir.path, 'split_left_$splitCalls.jpg');
    final rightPath = p.join(_tmpDir.path, 'split_right_$splitCalls.jpg');
    File(leftPath).writeAsBytesSync(img.encodeJpg(image));
    File(rightPath).writeAsBytesSync(img.encodeJpg(image));
    return SpreadSplitResult(
      leftPageImagePath: leftPath,
      rightPageImagePath: rightPath,
      confidence: 0.9,
      providerInfo: info,
    );
  }

  @override
  Future<DewarpResult> dewarp(
    String pageImagePath,
    Quad pageBounds, {
    String? outputPath,
  }) async {
    dewarpCalls++;
    final path = outputPath ?? pageImagePath;
    if (outputPath != null && outputPath != pageImagePath) {
      File(pageImagePath).copySync(outputPath);
    }
    return DewarpResult(
      flattenedImagePath: path,
      providerInfo: info,
      occlusionDetected: false,
      occlusionHighConfidenceTextLoss: false,
    );
  }
}

/// Polls [condition] instead of a fixed `Future.delayed`, so async capture
/// pipeline tests aren't flaky under a slow/loaded CI machine.
Future<void> _waitUntil(
  FutureOr<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
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

/// Minimal router so book Done can `pushReplacement` to Review.
Widget _wrapCaptureWithRouter({
  required CaptureViewModel viewModel,
  required String projectId,
}) {
  final router = GoRouter(
    initialLocation: AppRoutes.captureFor(projectId),
    routes: [
      GoRoute(
        path: AppRoutes.capture,
        builder: (context, state) =>
            CaptureScreen(projectId: projectId, viewModel: viewModel),
      ),
      GoRoute(
        path: AppRoutes.pageReview,
        builder: (context, state) => const Scaffold(
          body: Text('Review', key: ValueKey('pageReviewMarker')),
        ),
      ),
      GoRoute(
        path: AppRoutes.cropCorrection,
        builder: (context, state) => const Scaffold(
          body: Text('Crop', key: ValueKey('cropCorrectionMarker')),
        ),
      ),
    ],
  );
  return MaterialApp.router(
    routerConfig: router,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
  );
}

class _IdBatchCaptureProvider extends _TestCaptureProvider
    implements BatchDocumentCapture {
  _IdBatchCaptureProvider(super._tmpDir);

  final maxPagesSeen = <int>[];

  @override
  Future<List<StillCapture>> scanDocuments({int maxPages = 50}) async {
    maxPagesSeen.add(maxPages);
    return [await captureStill()];
  }
}

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
      dewarpProvider: _FakeBookDewarpProvider(tmpDir),
      detectionProvider: _FakeDetectionProvider(),
      enhancementProvider: enhancementProvider,
      fileStorage: paths,
    );
    permissionPlatform = FakePermissionHandlerPlatform();
    PermissionHandlerPlatform.instance = permissionPlatform;
  });

  CaptureViewModel buildViewModel({
    Duration resultPreviewHold = Duration.zero,
    String? replacePageId,
    CaptureSettings captureSettings = const CaptureSettings(),
    CaptureProvider? captureProviderOverride,
    CaptureMode? preferredCaptureMode,
  }) => CaptureViewModel(
    projectId: 'proj1',
    captureProvider: captureProviderOverride ?? captureProvider,
    capturePageUseCase: capturePageUseCase,
    processBookSpreadUseCase: processBookSpreadUseCase,
    projectRepository: projectRepository,
    pageRepository: pageRepository,
    settingsRepository: _FakeSettingsRepository(
      settings: AppSettings(captureSettings: captureSettings),
    ),
    replacePageId: replacePageId,
    preferredCaptureMode: preferredCaptureMode,
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
      // Continue + page badge only appear after the first page is captured.
      expect(find.byKey(const ValueKey('captureDoneButton')), findsNothing);
      expect(find.byKey(const ValueKey('capturePageCount')), findsNothing);
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
    expect(find.byKey(const ValueKey('capturePageCount')), findsOneWidget);
    expect(find.text('1'), findsWidgets);
    final pages = await pageRepository.getPages('proj1');
    expect(pages, hasLength(1));
  });

  // Exercised at the ViewModel level, not through a pumped CaptureScreen:
  // interleaving a still-in-flight `runAsync` future with widget pumps
  // (needed to observe the mid-processing state) isn't a supported
  // combination -- it hung rather than settling. A plain `test()` runs real
  // async normally, with no fake-async pump machinery to fight.
  test(
    'saves the photo and returns to the camera without processing it',
    () async {
      final gate = Completer<void>();
      enhancementProvider.enhanceGate = gate;
      final viewModel = buildViewModel();
      await viewModel.initialize();

      expect(viewModel.pageCount, 0);

      final captureFuture = viewModel.captureManually();
      await captureFuture;

      expect(viewModel.capturing, isFalse);
      expect(viewModel.frozenPreviewPath, isNull);
      expect(viewModel.resultPreviewPath, isNull);
      expect(viewModel.pageCount, 1);
      expect(gate.isCompleted, isFalse);
    },
  );

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

  test('does not hold a processed preview after the shot', () async {
    final viewModel = buildViewModel(
      resultPreviewHold: const Duration(milliseconds: 80),
    );
    await viewModel.initialize();

    await viewModel.captureManually();

    expect(viewModel.resultPreviewPath, isNull);
    expect(viewModel.frozenPreviewPath, isNull);
    expect(viewModel.pageCount, 1);
    expect(viewModel.capturing, isFalse);
  });

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

  // Same-timestamp frames stay below the 2000ms Auto stable window, so Auto
  // does not fire. Increasing timestamps are covered by the ViewModel test.
  testWidgets(
    'stable analysis frames with no elapsed capture window do not auto-fire',
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

  test(
    'auto-capture fires once after a 2000ms stable window, then waits for scene change',
    () async {
      captureProvider.analysisController =
          StreamController<FrameAnalysis>.broadcast();
      addTearDown(() => captureProvider.analysisController!.close());
      final viewModel = buildViewModel();
      await viewModel.initialize();
      viewModel.setAutoCaptureEnabled(true);
      expect(viewModel.autoCaptureEnabled, isTrue);

      FrameAnalysis stable(int ms) => FrameAnalysis(
        timestampMs: ms,
        documentDetected: true,
        quad: Quad.captureGuide,
        cornersStable: true,
        motionBelowThreshold: true,
        focusAcceptable: true,
        exposureAcceptable: true,
        warnings: const {},
        confidence: 0.8,
      );

      captureProvider.analysisController!.add(stable(0));
      captureProvider.analysisController!.add(stable(1000));
      captureProvider.analysisController!.add(stable(2100));
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(viewModel.pageCount, 1);

      captureProvider.analysisController!.add(stable(2300));
      captureProvider.analysisController!.add(stable(2800));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(viewModel.pageCount, 1);

      captureProvider.analysisController!.add(
        const FrameAnalysis(
          timestampMs: 3000,
          documentDetected: false,
          quad: null,
          cornersStable: false,
          motionBelowThreshold: false,
          focusAcceptable: true,
          exposureAcceptable: true,
          warnings: {},
        ),
      );
      captureProvider.analysisController!.add(stable(3200));
      captureProvider.analysisController!.add(stable(5300));
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(viewModel.pageCount, 2);
    },
  );

  test('manual mode does not auto-capture', () async {
    captureProvider.analysisController =
        StreamController<FrameAnalysis>.broadcast();
    addTearDown(() => captureProvider.analysisController!.close());
    final viewModel = buildViewModel();
    await viewModel.initialize();
    viewModel.setAutoCaptureEnabled(false);
    for (final ms in [0, 300, 700, 1000]) {
      captureProvider.analysisController!.add(
        FrameAnalysis(
          timestampMs: ms,
          documentDetected: true,
          quad: Quad.captureGuide,
          cornersStable: true,
          motionBelowThreshold: true,
          focusAcceptable: true,
          exposureAcceptable: true,
          warnings: const {},
          confidence: 0.8,
        ),
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(viewModel.pageCount, 0);
  });

  test(
    'a configured countdown delays the capture and reports remaining seconds',
    () async {
      final viewModel = buildViewModel(
        captureSettings: const CaptureSettings(countdownSeconds: 2),
      );
      await viewModel.initialize();

      final future = viewModel.captureManually();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(viewModel.countdownRemaining, 2);
      expect(viewModel.pageCount, 0);

      await Future<void>.delayed(const Duration(milliseconds: 1000));
      expect(viewModel.countdownRemaining, 1);
      expect(viewModel.pageCount, 0);

      await future;
      expect(viewModel.countdownRemaining, 0);
      expect(viewModel.pageCount, 1);
    },
  );

  test(
    'continuous capture re-arms immediately without requiring a scene change',
    () async {
      captureProvider.analysisController =
          StreamController<FrameAnalysis>.broadcast();
      addTearDown(() => captureProvider.analysisController!.close());
      final viewModel = buildViewModel(
        captureSettings: const CaptureSettings(
          autoCaptureEnabled: true,
          continuousCapture: true,
        ),
      );
      await viewModel.initialize();
      expect(viewModel.autoCaptureEnabled, isTrue);

      FrameAnalysis stable(int ms) => FrameAnalysis(
        timestampMs: ms,
        documentDetected: true,
        quad: Quad.captureGuide,
        cornersStable: true,
        motionBelowThreshold: true,
        focusAcceptable: true,
        exposureAcceptable: true,
        warnings: const {},
        confidence: 0.8,
      );

      // First stable window fires a capture.
      captureProvider.analysisController!.add(stable(0));
      captureProvider.analysisController!.add(stable(2100));
      await _waitUntil(() => viewModel.pageCount == 1);
      expect(viewModel.pageCount, 1);

      // A second stable window, with no intervening unstable frame, fires
      // again immediately -- unlike the non-continuous default, which
      // requires a scene change first (see the sibling test above).
      captureProvider.analysisController!.add(stable(2200));
      captureProvider.analysisController!.add(stable(4300));
      await _waitUntil(() => viewModel.pageCount == 2);
      expect(viewModel.pageCount, 2);
    },
  );

  test('haptic and audio confirmation fire only when enabled', () async {
    final hapticCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          hapticCalls.add(call);
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    final viewModel = buildViewModel(
      captureSettings: const CaptureSettings(
        hapticConfirmation: true,
        audioConfirmation: true,
      ),
    );
    await viewModel.initialize();
    await viewModel.captureManually();

    expect(
      hapticCalls.map((c) => c.method),
      containsAll(['HapticFeedback.vibrate', 'SystemSound.play']),
    );
  });

  test('haptic and audio confirmation stay silent when disabled', () async {
    final hapticCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          hapticCalls.add(call);
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    final viewModel = buildViewModel(
      captureSettings: const CaptureSettings(
        hapticConfirmation: false,
        audioConfirmation: false,
      ),
    );
    await viewModel.initialize();
    await viewModel.captureManually();

    expect(
      hapticCalls.map((c) => c.method),
      isNot(
        anyOf(contains('HapticFeedback.vibrate'), contains('SystemSound.play')),
      ),
    );
  });

  testWidgets(
    'tapping Continue with no pages does nothing visible (button hidden)',
    (tester) async {
      final viewModel = buildViewModel();
      await tester.pumpWidget(
        _wrap(CaptureScreen(projectId: 'proj1', viewModel: viewModel)),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const ValueKey('captureDoneButton')), findsNothing);
      expect(find.byKey(const ValueKey('captureNameField')), findsNothing);
    },
  );

  testWidgets('Continue appears after a page is captured', (tester) async {
    final viewModel = buildViewModel();
    await tester.pumpWidget(
      _wrap(CaptureScreen(projectId: 'proj1', viewModel: viewModel)),
    );
    await tester.pump();
    await tester.pump();

    await tester.runAsync(() => viewModel.captureManually());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('captureDoneButton')), findsOneWidget);
    expect(find.text('Continue'), findsWidgets);
    expect(find.byKey(const ValueKey('captureNameField')), findsNothing);
  });

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
        settingsRepository: _FakeSettingsRepository(),
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

  test('quality warnings do not block a manual shutter tap', () async {
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

    final pages = await viewModel.captureManually();
    expect(pages, isNotEmpty);
    expect(viewModel.pageCount, 1);
  });

  test(
    'a book capture stores one full page even if the project was a spread',
    () async {
      projectRepository.nextProject = Project(
        id: 'proj1',
        type: ProjectType.book,
        title: 'Book',
        metadata: const ProjectMetadata(
          bookScanMode: BookScanMode.twoPageSpread,
        ),
        pageOrder: const [],
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        processingState: ProcessingState.idle,
      );
      final viewModel = buildViewModel();
      await viewModel.initialize();
      final pages = await viewModel.captureManually();
      expect(pages, hasLength(1));
      expect(viewModel.pageCount, 1);
      expect(pages.single.spreadSiblingPageId, isNull);
      expect(pages.single.cropPoints, Quad.fullFrame);
      expect(pages.single.status, PageStatus.processing);
      await _waitUntil(() async {
        final saved = await pageRepository.getPage(pages.single.id);
        return saved?.status == PageStatus.ready;
      });
    },
  );

  test('a book single-page capture persists the full photo', () async {
    projectRepository.nextProject = Project(
      id: 'proj1',
      type: ProjectType.book,
      title: 'Book',
      metadata: const ProjectMetadata(bookScanMode: BookScanMode.singlePage),
      pageOrder: const [],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      processingState: ProcessingState.idle,
    );
    final viewModel = buildViewModel();
    await viewModel.initialize();
    final pages = await viewModel.captureManually();
    expect(pages, hasLength(1));
    expect(viewModel.pageCount, 1);
    expect(pages.single.spreadSiblingPageId, isNull);
    expect(pages.single.cropPoints, Quad.fullFrame);
    expect(pages.single.status, PageStatus.processing);
    expect(pages.single.stages[PipelineStage.dewarp], isNull);
    expect(pages.single.stages[PipelineStage.split], isNull);
    await _waitUntil(() async {
      final saved = await pageRepository.getPage(pages.single.id);
      return saved?.status == PageStatus.ready &&
          saved?.filter == PageFilter.enhancedColor;
    });
  });

  test('book shutter does not open the multi-page document scanner', () async {
    final batch = _IdBatchCaptureProvider(tmpDir);
    projectRepository.nextProject = Project(
      id: 'proj1',
      type: ProjectType.book,
      title: 'Book',
      metadata: const ProjectMetadata(),
      pageOrder: const [],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      processingState: ProcessingState.idle,
    );
    final gate = Completer<void>();
    enhancementProvider.enhanceGate = gate;
    final viewModel = buildViewModel(captureProviderOverride: batch);
    await viewModel.initialize();

    final pages = await viewModel.captureManually();
    expect(batch.maxPagesSeen, isEmpty);
    expect(viewModel.capturing, isFalse);
    expect(pages.single.status, PageStatus.processing);

    gate.complete();
    await _waitUntil(() async {
      final saved = await pageRepository.getPage(pages.single.id);
      return saved?.status == PageStatus.ready;
    });
  });

  test(
    'book shutter clears while enhancement is still running',
    () async {
      projectRepository.nextProject = Project(
        id: 'proj1',
        type: ProjectType.book,
        title: 'Book',
        metadata: const ProjectMetadata(),
        pageOrder: const [],
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        processingState: ProcessingState.idle,
      );
      final gate = Completer<void>();
      enhancementProvider.enhanceGate = gate;
      final viewModel = buildViewModel();
      await viewModel.initialize();

      final pages = await viewModel.captureManually();
      expect(viewModel.capturing, isFalse);
      expect(pages.single.status, PageStatus.processing);
      expect(gate.isCompleted, isFalse);

      final mid = await pageRepository.getPage(pages.single.id);
      expect(mid?.status, PageStatus.processing);

      gate.complete();
      await _waitUntil(() async {
        final saved = await pageRepository.getPage(pages.single.id);
        return saved?.status == PageStatus.ready;
      });
      final done = await pageRepository.getPage(pages.single.id);
      expect(done?.filter, PageFilter.enhancedColor);
      expect(done?.stages[PipelineStage.enhancement], isNotNull);
    },
  );

  testWidgets('book Done opens Review instead of post-capture crop', (
    tester,
  ) async {
    projectRepository.nextProject = Project(
      id: 'proj1',
      type: ProjectType.book,
      title: 'Book',
      metadata: const ProjectMetadata(),
      pageOrder: const [],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      processingState: ProcessingState.idle,
    );
    final viewModel = buildViewModel();
    await tester.pumpWidget(
      _wrapCaptureWithRouter(viewModel: viewModel, projectId: 'proj1'),
    );
    await tester.pump();
    await tester.pump();

    await tester.runAsync(() => viewModel.captureManually());
    await tester.pump();

    expect(find.byKey(const ValueKey('captureDoneButton')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('captureDoneButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('pageReviewMarker')), findsOneWidget);
    expect(find.byKey(const ValueKey('cropCorrectionMarker')), findsNothing);
  });

  testWidgets('ID capture asks for the front, then the back', (tester) async {
    final viewModel = buildViewModel(preferredCaptureMode: CaptureMode.idCard);
    await tester.pumpWidget(
      _wrap(CaptureScreen(projectId: 'proj1', viewModel: viewModel)),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Scan the front'), findsOneWidget);
    expect(find.text('Scan front'), findsOneWidget);
    expect(find.byKey(const ValueKey('captureDoneButton')), findsNothing);

    await tester.runAsync(() => viewModel.captureManually());
    await tester.pump();

    expect(viewModel.pageCount, 1);
    expect(viewModel.idScanFinished, isFalse);
    expect(find.text('Scan the back'), findsOneWidget);
    expect(find.text('Scan back'), findsOneWidget);
    expect(find.byKey(const ValueKey('captureDoneButton')), findsNothing);
    final pages = await pageRepository.getPages('proj1');
    expect(pages.single.logicalPageLabel, 'Front');
  });

  test(
    'ID scan saves one side at a time and finishes after the back',
    () async {
      final batch = _IdBatchCaptureProvider(tmpDir);
      final viewModel = buildViewModel(
        captureProviderOverride: batch,
        preferredCaptureMode: CaptureMode.idCard,
      );
      viewModel.idFrontLabel = 'Front';
      viewModel.idBackLabel = 'Back';
      await viewModel.initialize();

      final front = await viewModel.captureManually();
      expect(batch.maxPagesSeen, [1]);
      expect(front.single.logicalPageLabel, 'Front');
      expect(viewModel.idScanFinished, isFalse);

      final back = await viewModel.captureManually();
      expect(batch.maxPagesSeen, [1, 1]);
      expect(back.single.logicalPageLabel, 'Back');
      expect(viewModel.idScanFinished, isTrue);
      expect(viewModel.pageCount, 2);
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
    expect(find.byKey(const ValueKey('captureFrameGuide')), findsNothing);
    expect(find.byKey(const ValueKey('captureFlashButton')), findsOneWidget);
    expect(find.byKey(const ValueKey('captureAutoToggle')), findsOneWidget);
    expect(find.byKey(const ValueKey('captureImportButton')), findsOneWidget);
    expect(find.byKey(const ValueKey('shutterButton')), findsOneWidget);
  });

  testWidgets('Auto/Manual toggle switches capture mode', (tester) async {
    final viewModel = buildViewModel();
    await tester.pumpWidget(
      _wrap(CaptureScreen(projectId: 'proj1', viewModel: viewModel)),
    );
    await tester.pump();
    await tester.pump();

    expect(viewModel.autoCaptureEnabled, isFalse);
    expect(find.text('Manual'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('captureAutoToggle')));
    await tester.pump();

    expect(viewModel.autoCaptureEnabled, isTrue);
    expect(find.text('Auto'), findsOneWidget);
  });
}
