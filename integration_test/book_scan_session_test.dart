import 'dart:io';
import 'dart:math';

import 'package:bookscanner/data/services/local/app_paths.dart';
import 'package:bookscanner/data/services/ocr/adapters/fake_ocr_provider.dart';
import 'package:bookscanner/domain/models/capture_models.dart';
import 'package:bookscanner/domain/models/geometry.dart';
import 'package:bookscanner/domain/models/provider_info.dart';
import 'package:bookscanner/domain/models/scan_page.dart';
import 'package:bookscanner/domain/providers/capture_provider.dart';
import 'package:bookscanner/domain/providers/ocr_provider.dart';
import 'package:bookscanner/domain/repositories/page_repository.dart';
import 'package:bookscanner/main.dart';
import 'package:bookscanner/routing/app_router.dart';
import 'package:bookscanner/ui/core/di/service_locator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import 'support/post_capture_helpers.dart';

/// Stands in for the system document scanner (ML Kit / VisionKit) that
/// book mode opens: each scan returns [pagesPerScan] real JPEGs marked
/// `nativeReady`, as Google's scanner returns already-flattened pages.
/// `analysisStream()` never emits, so nothing fires an unrequested capture.
class _SystemScannerDouble implements CaptureProvider, BatchDocumentCapture {
  _SystemScannerDouble(this._tmpDir);

  /// Pages each scan returns, as if the user kept two shots.
  static const pagesPerScan = 2;

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
      analyzedFromStill: true,
      detectionConfidence: 1,
      nativeReady: true,
    );
  }

  @override
  Future<List<StillCapture>> scanDocuments({int maxPages = 50}) async => [
    for (var i = 0; i < pagesPerScan && i < maxPages; i++) await captureStill(),
  ];

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
/// end -- scan two pages, split a photographed spread, correct a recognized
/// OCR block, export as Markdown -- using fake scanner and OCR adapters so it is
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
      () => _SystemScannerDouble(paths.tmpDir),
    );

    if (locator.isRegistered<OcrProvider>()) {
      locator.unregister<OcrProvider>();
    }
    locator.registerSingleton<OcrProvider>(FakeOcrProvider());
  });

  testWidgets(
    'book mode: scan two pages, split a spread, correct OCR text, export as Markdown',
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

      // Continue opens the system scanner straight away (no camera screen
      // or permission rationale of our own); its two pages land in Review.
      expect(find.byKey(const ValueKey('pageReviewList')), findsOneWidget);
      expect(find.byKey(const ValueKey('shutterButton')), findsNothing);
      final projectId = GoRouter.of(
        tester.element(find.byKey(const ValueKey('pageReviewList'))),
      ).state.pathParameters['projectId']!;

      Future<List<ScanPage>> orderedPages() async =>
          (await locator<PageRepository>().getPages(projectId))
            ..sort((a, b) => a.sequence.compareTo(b.sequence));

      var pages = await orderedPages();
      expect(pages, hasLength(2));
      expect(
        pages.map((page) => page.spreadSiblingPageId),
        everyElement(isNull),
      );

      // The first "page" was a photographed open spread: split it in two.
      await tester.tap(find.byKey(ValueKey('pageMenu-${pages.first.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Split into two pages'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      pages = await orderedPages();
      expect(pages, hasLength(3));
      expect(pages[0].spreadSiblingPageId, pages[1].id);
      expect(pages[1].spreadSiblingPageId, pages[0].id);
      expect(pages[2].spreadSiblingPageId, isNull);

      // Review no longer offers "Recognize text" (export runs OCR); open the
      // OCR screen directly to correct one recognized block.
      expect(find.text('Recognize text'), findsNothing);
      GoRouter.of(
        tester.element(find.byKey(const ValueKey('pageReviewList'))),
      ).push(AppRoutes.ocrReviewFor(projectId, pages.first.id));
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

      await exportFromReviewSheet(tester, 'reviewExportMarkdown');

      expect(
        find.byKey(const ValueKey('exportCompleteMessage')),
        findsOneWidget,
      );
    },
  );
}
