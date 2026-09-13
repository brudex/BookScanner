import 'dart:io';
import 'dart:math';

import 'package:bookscanner/domain/models/capture_models.dart';
import 'package:bookscanner/domain/models/geometry.dart';
import 'package:bookscanner/domain/models/provider_info.dart';
import 'package:bookscanner/domain/providers/capture_provider.dart';
import 'package:bookscanner/domain/providers/page_detection_provider.dart';
import 'package:bookscanner/domain/repositories/page_repository.dart';
import 'package:bookscanner/main.dart';
import 'package:bookscanner/ui/core/di/service_locator.dart';
import 'package:bookscanner/ui/features/capture/views/capture_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

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
    final path = p.join(_tmpDir.path, 'fallback_capture_$_captureCount.jpg');
    await File(path).writeAsBytes(img.encodeJpg(image, quality: 90));

    return StillCapture(
      originalImagePath: path,
      detectedQuad: null, // forces the app to call PageDetectionProvider
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

/// Always fails, simulating an unavailable/crashed detection model --
/// exactly the "provider failure" scenario SPEC 9.7 and SPEC 13 ("provider
/// fallback") describe.
class _AlwaysThrowingDetectionProvider implements PageDetectionProvider {
  @override
  ProviderInfo get info => const ProviderInfo(
    providerName: 'integration-test-throwing-detection',
    adapterVersion: '1.0.0-test',
  );

  @override
  Future<Quad?> detectQuad(String imagePath) => throw const ProviderException(
    ProviderErrorCategory.modelUnavailable,
    'Detection model unavailable (simulated failure)',
  );
}

/// SPEC 13: "Integration tests must cover: ... provider fallback ...".
/// SPEC 9.7: "A provider failure or unavailable model may fall back to
/// manual capture, basic perspective correction... without losing the
/// user's confirmed source image."
///
/// This test's `PageDetectionProvider` always throws. Crop finding now
/// runs inside `ImageEnhancementProvider.enhance(detectCrop: true)`, so
/// a throwing detection provider is unused on the capture path. The
/// capture still completes and the page is saved (full-bleed synthetic
/// still → no crop → full-frame), which is the SPEC 9.7 outcome: never
/// discard the already-captured original image.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await setupServiceLocator();
    final tmpDir = await Directory.systemTemp.createTemp(
      'provider_fallback_test_',
    );
    if (locator.isRegistered<CaptureProvider>()) {
      locator.unregister<CaptureProvider>();
    }
    locator.registerFactory<CaptureProvider>(
      () => _ManualOnlyCaptureProvider(tmpDir),
    );
    if (locator.isRegistered<PageDetectionProvider>()) {
      locator.unregister<PageDetectionProvider>();
    }
    locator.registerSingleton<PageDetectionProvider>(
      _AlwaysThrowingDetectionProvider(),
    );
  });

  testWidgets(
    'a capture still succeeds and is saved when the detection provider fails',
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

      // The capture must succeed and be reflected on screen, not silently
      // swallowed by the (now-caught) detection failure.
      expect(find.text('1 page scanned'), findsOneWidget);

      final pages = await locator<PageRepository>().getPages(projectId);
      expect(pages, hasLength(1));
      expect(File(pages.single.originalImagePath).existsSync(), isTrue);
      // Fell back to the full-frame crop, same as a clean "no quad found"
      // result would.
      expect(pages.single.cropPoints, Quad.fullFrame);
    },
  );
}
