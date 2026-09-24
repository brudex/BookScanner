import 'dart:io';
import 'dart:math';

import 'package:bookscanner/domain/models/capture_models.dart';
import 'package:bookscanner/domain/models/geometry.dart';
import 'package:bookscanner/domain/models/provider_info.dart';
import 'package:bookscanner/domain/providers/capture_provider.dart';
import 'package:bookscanner/domain/repositories/page_repository.dart';
import 'package:bookscanner/main.dart';
import 'package:bookscanner/ui/core/di/service_locator.dart';
import 'package:bookscanner/ui/features/capture/views/capture_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import 'support/post_capture_helpers.dart';

/// Manual-only capture provider double, identical in spirit to the one in
/// `book_scan_session_test.dart`/`interrupted_session_recovery_test.dart`.
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
    // Each capture gets a distinct fill shade so a test can confirm the
    // *content* actually changed after a rescan, not just its timestamp.
    final image = img.Image(width: 1240, height: 1754);
    img.fill(
      image,
      color: img.ColorRgb8(200 + rand.nextInt(50), 30, 30 + _captureCount * 10),
    );
    final path = p.join(_tmpDir.path, 'rescan_capture_$_captureCount.jpg');
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

/// SPEC 13: "Integration tests must cover: ... page reorder/rescan ...".
/// Drives the real "Rescan" popup-menu action end to end: capture a page,
/// go to Review, tap Rescan, capture again, and confirm the *same* page was
/// replaced in place (same id, same total page count) rather than a new
/// page being appended.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await setupServiceLocator();
    final tmpDir = await Directory.systemTemp.createTemp('rescan_test_');
    if (locator.isRegistered<CaptureProvider>()) {
      locator.unregister<CaptureProvider>();
    }
    locator.registerFactory<CaptureProvider>(
      () => _ManualOnlyCaptureProvider(tmpDir),
    );
  });

  testWidgets(
    'rescanning a page replaces its image content in place instead of appending a new page',
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
      expect(find.byKey(const ValueKey('capturePageCount')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('captureDoneButton')));
      await tester.pumpAndSettle();
      await advancePostCapturePage(tester);
      await tester.tap(find.byKey(const ValueKey('captureNameSaveButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pageReviewList')), findsOneWidget);

      final pageRepository = locator<PageRepository>();
      final beforePages = await pageRepository.getPages(projectId);
      expect(beforePages, hasLength(1));
      final originalPageId = beforePages.single.id;
      final originalImagePath = beforePages.single.originalImagePath;

      await tester.tap(find.byKey(ValueKey('pageMenu-$originalPageId')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rescan'));
      await tester.pumpAndSettle();

      // Back in Capture, now in replace mode.
      expect(find.byKey(const ValueKey('shutterButton')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('shutterButton')));
      await tester.pumpAndSettle();

      // A rescan is single-shot: the screen navigates back to Review on its
      // own once the replacement capture completes, without tapping "Done".
      expect(find.byKey(const ValueKey('pageReviewList')), findsOneWidget);

      final afterPages = await pageRepository.getPages(projectId);
      expect(afterPages, hasLength(1)); // replaced, not appended
      expect(afterPages.single.id, originalPageId);
      expect(afterPages.single.originalImagePath, isNot(originalImagePath));
      expect(File(afterPages.single.originalImagePath).existsSync(), isTrue);
    },
  );
}
