import 'dart:io';
import 'dart:math';

import 'package:bookscanner/domain/models/capture_models.dart';
import 'package:bookscanner/domain/models/geometry.dart';
import 'package:bookscanner/domain/models/provider_info.dart';
import 'package:bookscanner/domain/providers/capture_provider.dart';
import 'package:bookscanner/domain/repositories/export_job_repository.dart';
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
    final path = p.join(_tmpDir.path, 'export_capture_$_captureCount.jpg');
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

/// SPEC 13: "Integration tests must cover: ... PDF/Markdown/DOCX export
/// ...". `book_scan_session_test.dart` already covers Markdown end to end;
/// this file covers the other two formats, each capturing its own fresh
/// project (`ExportScreen` has no "start over" action once a job exists, so
/// two formats need two independent sessions, not one export screen reused
/// twice).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await setupServiceLocator();
    final tmpDir = await Directory.systemTemp.createTemp(
      'pdf_docx_export_test_',
    );
    if (locator.isRegistered<CaptureProvider>()) {
      locator.unregister<CaptureProvider>();
    }
    locator.registerFactory<CaptureProvider>(
      () => _ManualOnlyCaptureProvider(tmpDir),
    );
  });

  Future<String> captureOnePageAndReachReview(WidgetTester tester) async {
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
    return projectId;
  }

  testWidgets(
    'exporting a captured project as an image PDF produces a real file',
    (tester) async {
      final projectId = await captureOnePageAndReachReview(tester);

      await exportFromReviewSheet(tester, 'reviewExportPdf');

      expect(
        find.byKey(const ValueKey('exportCompleteMessage')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('exportShareButton')), findsOneWidget);

      final jobs = await locator<ExportJobRepository>()
          .watchJobsForProject(projectId)
          .first;
      expect(jobs, hasLength(1));
      final outputPath = jobs.single.outputPath;
      expect(outputPath, isNotNull);
      final bytes = await File(outputPath!).readAsBytes();
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    },
  );

  testWidgets('exporting a captured project as DOCX produces a real file', (
    tester,
  ) async {
    final projectId = await captureOnePageAndReachReview(tester);

    await exportFromReviewSheet(tester, 'reviewExportWord');

    expect(find.byKey(const ValueKey('exportCompleteMessage')), findsOneWidget);
    expect(find.byKey(const ValueKey('exportShareButton')), findsOneWidget);

    final jobs = await locator<ExportJobRepository>()
        .watchJobsForProject(projectId)
        .first;
    expect(jobs, hasLength(1));
    final outputPath = jobs.single.outputPath;
    expect(outputPath, isNotNull);
    // A DOCX is a real zip archive -- the local file header signature is
    // 'PK\x03\x04'.
    final bytes = await File(outputPath!).readAsBytes();
    expect(bytes.take(4).toList(), [0x50, 0x4B, 0x03, 0x04]);
  });
}
