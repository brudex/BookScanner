import 'package:bookscanner/data/services/scanner/adapters/mode_aware_capture_provider.dart';
import 'package:bookscanner/domain/models/capture_models.dart';
import 'package:bookscanner/domain/models/provider_info.dart';
import 'package:bookscanner/domain/providers/capture_provider.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingCapture implements CaptureProvider, BatchDocumentCapture {
  _RecordingCapture(this.name);

  final String name;
  CaptureMode? lastMode;
  int openCount = 0;
  int closeCount = 0;
  int stillCount = 0;
  int scanCount = 0;

  @override
  ProviderInfo get info =>
      ProviderInfo(providerName: name, adapterVersion: '1');

  @override
  int? get previewTextureId => null;

  @override
  double get previewAspectRatio => 4 / 3;

  @override
  Future<ScannerCapabilities> capabilities() async => const ScannerCapabilities(
    liveEdgeDetection: false,
    offlineOcr: false,
    handwritingOcr: false,
    bookDewarping: false,
    fingerRemoval: false,
    supportedOcrLanguages: {},
    torch: false,
    opticalZoom: false,
  );

  @override
  Future<void> openSession(CaptureMode mode) async {
    lastMode = mode;
    openCount++;
  }

  @override
  Stream<FrameAnalysis> analysisStream() => const Stream.empty();

  @override
  Future<StillCapture> captureStill({bool bypassQualityGate = false}) async {
    stillCount++;
    return StillCapture(
      originalImagePath: '$name.jpg',
      detectedQuad: null,
      qualityScore: 1,
      warnings: const {},
      capturedAtMs: 0,
      providerInfo: info,
    );
  }

  @override
  Future<List<StillCapture>> scanDocuments({int maxPages = 50}) async {
    scanCount++;
    return [await captureStill()];
  }

  @override
  Future<void> setFlashMode(FlashMode mode) async {}

  @override
  Future<void> setZoom(double level) async {}

  @override
  Future<void> setFocusAndExposurePoint(double x, double y) async {}

  @override
  Future<void> closeSession() async {
    closeCount++;
  }
}

void main() {
  test('document sessions use the document backend', () async {
    final document = _RecordingCapture('document');
    final book = _RecordingCapture('book');
    final provider = ModeAwareCaptureProvider(document: document, book: book);

    await provider.openSession(CaptureMode.singlePage);
    expect(document.openCount, 1);
    expect(book.openCount, 0);

    await provider.scanDocuments();
    expect(document.scanCount, 1);
    expect(book.scanCount, 0);
  });

  test('book sessions switch to the camera backend', () async {
    final document = _RecordingCapture('document');
    final book = _RecordingCapture('book');
    final provider = ModeAwareCaptureProvider(document: document, book: book);

    await provider.openSession(CaptureMode.bookSpread);
    expect(document.closeCount, 1);
    expect(book.openCount, 1);
    expect(book.lastMode, CaptureMode.bookSpread);

    await provider.captureStill();
    expect(book.stillCount, 1);
    expect(document.stillCount, 0);
  });
}
