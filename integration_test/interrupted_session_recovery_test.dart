import 'dart:io';
import 'dart:math';

import 'package:bookscanner/data/services/local/app_paths.dart';
import 'package:bookscanner/domain/models/capture_models.dart';
import 'package:bookscanner/domain/models/geometry.dart';
import 'package:bookscanner/domain/models/provider_info.dart';
import 'package:bookscanner/domain/providers/capture_provider.dart';
import 'package:bookscanner/domain/repositories/page_repository.dart';
import 'package:bookscanner/main.dart';
import 'package:bookscanner/routing/app_router.dart';
import 'package:bookscanner/ui/core/di/service_locator.dart';
import 'package:bookscanner/ui/features/capture/views/capture_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

/// Manual-only capture provider double, identical in spirit to the one in
/// `book_scan_session_test.dart` (see that file's doc comment for why
/// `analysisStream()` stays empty rather than reusing `FakeCaptureProvider`).
class _ManualOnlyCaptureProvider implements CaptureProvider {
  _ManualOnlyCaptureProvider(this._tmpDir);

  final Directory _tmpDir;
  int _captureCount = 0;
  bool _sessionOpen = false;

  @override
  int? get previewTextureId => null;

  @override
  double get previewAspectRatio => 4 / 3;

  @override
  ProviderInfo get info => const ProviderInfo(
    providerName: 'integration-test-capture',
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
    _sessionOpen = true;
  }

  @override
  Stream<FrameAnalysis> analysisStream() => const Stream.empty();

  @override
  Future<StillCapture> captureStill({bool bypassQualityGate = false}) async {
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
    final path = p.join(_tmpDir.path, 'recovery_capture_$_captureCount.jpg');
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

/// SPEC 13: "Integration tests must cover: ... interrupted-session
/// recovery ...". SPEC 9.2 requires that "the original still image [is
/// persisted] immediately" -- not deferred to some later "save" action --
/// specifically so a captured page survives the app being killed
/// mid-session. This test proves that by capturing a page and *never*
/// tapping "Done", then discarding and rebuilding the entire widget tree
/// (a fresh `BookScannerApp()`, simulating a cold app relaunch) while the
/// real on-disk SQLite database and image files from `setupServiceLocator()`
/// stay exactly as a real process kill would have left them. If the page
/// were only durably saved on "Done", it would be silently lost here.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await setupServiceLocator();
    final paths = locator<AppPaths>();
    if (locator.isRegistered<CaptureProvider>()) {
      locator.unregister<CaptureProvider>();
    }
    locator.registerFactory<CaptureProvider>(
      () => _ManualOnlyCaptureProvider(paths.tmpDir),
    );
  });

  testWidgets(
    'a captured page survives an unclean app restart before "Done" is tapped',
    (tester) async {
      await tester.pumpWidget(const BookScannerApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('newScanFab')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('newScanModeDocument')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('shutterButton')),
        findsOneWidget,
        reason:
            'Camera permission must be pre-granted for this deterministic '
            'flow, e.g. `adb shell pm grant <applicationId> '
            'android.permission.CAMERA` before running on a fresh '
            'emulator/device.',
      );
      final projectId = tester
          .widget<CaptureScreen>(find.byType(CaptureScreen))
          .projectId;

      await tester.tap(find.byKey(const ValueKey('shutterButton')));
      await tester.pumpAndSettle();
      expect(find.text('1 page scanned'), findsOneWidget);

      // Interrupt the session here -- deliberately never tap "Done".
      // Discard the whole widget tree and rebuild the app from scratch to
      // simulate a cold relaunch. `setupServiceLocator()` (and the real
      // SQLite connection/files it opened) is untouched by this, matching
      // what actually happens on a real process kill followed by a real
      // relaunch (which re-opens the same on-disk database and files).
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.pumpWidget(const BookScannerApp());
      await tester.pumpAndSettle();

      // `appRouter` is a top-level singleton, so it (unlike a real app
      // process) survives the widget-tree rebuild above with whatever
      // route it was last on -- explicitly return to Library rather than
      // relying on that GoRouter behavior, since navigation-stack reset is
      // not what this test is verifying (data durability is).
      appRouter.go(AppRoutes.library);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('libraryTitle')), findsOneWidget);
      expect(find.byKey(ValueKey('project-$projectId')), findsOneWidget);

      await tester.tap(find.byKey(ValueKey('project-$projectId')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('pageReviewList')), findsOneWidget);
      final pages = await locator<PageRepository>().getPages(projectId);
      expect(pages, hasLength(1));
      expect(File(pages.single.originalImagePath).existsSync(), isTrue);

      // Confirm the recovered project is still fully usable, not just
      // displaying stale data: add one more page to it.
      await tester.tap(find.byKey(const ValueKey('reviewAddPageButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('shutterButton')));
      await tester.pumpAndSettle();
      expect(find.text('2 pages scanned'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('captureDoneButton')));
      await tester.pumpAndSettle();
      // "Done" now prompts to name the scan (defaulted to a timestamp)
      // before navigating -- accept the default rather than typing a name.
      await tester.tap(find.byKey(const ValueKey('captureNameSaveButton')));
      await tester.pumpAndSettle();

      final finalPages = await locator<PageRepository>().getPages(projectId);
      expect(finalPages, hasLength(2));
    },
  );
}
