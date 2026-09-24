import 'dart:io';
import 'dart:math';

import 'package:bookscanner/data/services/local/app_paths.dart';
import 'package:bookscanner/data/services/ocr/adapters/fake_ocr_provider.dart';
import 'package:bookscanner/domain/models/capture_models.dart';
import 'package:bookscanner/domain/models/geometry.dart';
import 'package:bookscanner/domain/models/provider_info.dart';
import 'package:bookscanner/domain/providers/capture_provider.dart';
import 'package:bookscanner/domain/providers/ocr_provider.dart';
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

/// A capture provider double for this integration test: like
/// `FakeCaptureProvider` (used elsewhere for contract tests), it writes real
/// JPEGs so downstream pipeline stages (split/dewarp/enhance) operate on
/// genuine files -- but unlike it, `analysisStream()` never emits a frame.
/// `FakeCaptureProvider`'s synthetic frames always report every auto-capture
/// gate satisfied, which fires one extra, unrequested capture ~600ms after
/// the session opens; fine for the existing manual-smoke-test style of
/// `capture_flow_test.dart`, but it would make this test's page-count
/// assertions racy against real wall-clock timing. Keeping the session
/// purely manual makes the expected page count exactly `2 * shutter taps`
/// (book mode splits every capture into two pages).
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
    final path = p.join(_tmpDir.path, 'integration_capture_$_captureCount.jpg');
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

/// SPEC 13: "Integration tests must cover: ... document capture with a fake
/// adapter, multi-page book session, ... OCR correction, PDF/Markdown/DOCX
/// export ...". This test drives one realistic book-mode session end to
/// end -- capture two spreads, correct a recognized OCR block, export as
/// Markdown -- using the fake capture and OCR adapters so it is
/// deterministic and platform-independent (no dependency on the real
/// camera/ML pipeline). Run on both an Android emulator/device and an iOS
/// simulator/device per SPEC 13.
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

    if (locator.isRegistered<OcrProvider>()) {
      locator.unregister<OcrProvider>();
    }
    locator.registerSingleton<OcrProvider>(FakeOcrProvider());
  });

  testWidgets(
    'book mode: capture two spreads with a fake adapter, correct OCR text, export as Markdown',
    (tester) async {
      await tester.pumpWidget(const BookScannerApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('newScanFab')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('newScanModeBook')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('bookSetupCopyrightAck')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('bookSetupContinueButton')));
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

      // Two manual captures -> 4 pages (book mode splits every spread photo
      // into a left/right page pair).
      await tester.tap(find.byKey(const ValueKey('shutterButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('shutterButton')));
      await tester.pumpAndSettle();
      expect(find.text('4'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('captureDoneButton')));
      await tester.pumpAndSettle();
      // Continue → crop → filters per page → name → review.
      for (var i = 0; i < 4; i++) {
        await advancePostCapturePage(tester);
      }
      await tester.tap(find.byKey(const ValueKey('captureNameSaveButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('pageReviewList')), findsOneWidget);
      final pages = await locator<PageRepository>().getPages(projectId);
      expect(pages, hasLength(4));
      expect(
        pages.map((page) => page.spreadSiblingPageId),
        everyElement(isNotNull),
      );

      // Run OCR on the first page and correct one recognized block.
      await tester.tap(find.byKey(ValueKey('pageMenu-${pages.first.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recognize text'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('ocrRunButton')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ocrRunButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('ocrBlockList')), findsOneWidget);
      expect(find.text('Chapter One'), findsOneWidget);

      await tester.tap(find.text('Chapter One'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('ocrEditBlockField')),
        'Chapter One: The Beginning',
      );
      await tester.tap(find.byKey(const ValueKey('ocrEditBlockSaveButton')));
      await tester.pumpAndSettle();

      expect(find.text('Chapter One: The Beginning'), findsOneWidget);

      // Back to review, then export the whole project as Markdown.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pageReviewList')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('reviewExportButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('exportFormatMarkdown')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('exportCompleteMessage')),
        findsOneWidget,
      );
    },
  );
}
