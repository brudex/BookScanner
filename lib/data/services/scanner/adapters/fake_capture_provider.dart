import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../../../domain/models/capture_models.dart';
import '../../../../domain/models/geometry.dart';
import '../../../../domain/models/provider_info.dart';
import '../../../../domain/providers/capture_provider.dart';
import '../../local/app_paths.dart';

/// Deterministic in-memory capture provider used by contract/unit/widget/
/// integration tests (SPEC 13: "Integration tests must cover: ... document
/// capture with a fake adapter"). Not wired into the production composition
/// root on Android or iOS — those use `cunning_document_scanner`.
/// Generates a real JPEG file on disk (not an in-memory-only stub) so
/// downstream enhancement/OCR/export pipeline stages under test operate on
/// genuine files, matching the file-path-only boundary contract.
class FakeCaptureProvider implements CaptureProvider {
  FakeCaptureProvider({
    required AppPaths paths,
    ScannerCapabilities? capabilities,
  }) : _paths = paths,
       _capabilities =
           capabilities ??
           const ScannerCapabilities(
             liveEdgeDetection: true,
             offlineOcr: true,
             handwritingOcr: false,
             bookDewarping: true,
             fingerRemoval: false,
             supportedOcrLanguages: {'en'},
             torch: true,
             opticalZoom: true,
           );

  final AppPaths _paths;
  final ScannerCapabilities _capabilities;
  final _analysisController = StreamController<FrameAnalysis>.broadcast();
  Timer? _analysisTimer;
  int _captureCount = 0;
  bool _sessionOpen = false;

  @override
  int? get previewTextureId => null;

  @override
  double get previewAspectRatio => 4 / 3;

  @override
  ProviderInfo get info => const ProviderInfo(
    providerName: 'fake-capture',
    adapterVersion: '1.0.0-test',
  );

  @override
  Future<ScannerCapabilities> capabilities() async => _capabilities;

  @override
  Future<void> openSession(CaptureMode mode) async {
    _sessionOpen = true;
    _analysisTimer?.cancel();
    _analysisTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!_sessionOpen || _analysisController.isClosed) return;
      _analysisController.add(
        FrameAnalysis(
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          documentDetected: true,
          quad: Quad.fullFrame,
          cornersStable: true,
          motionBelowThreshold: true,
          focusAcceptable: true,
          exposureAcceptable: true,
          warnings: const {},
          confidence: 1,
        ),
      );
    });
  }

  @override
  Stream<FrameAnalysis> analysisStream() => _analysisController.stream;

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
    final path = p.join(_paths.tmpDir.path, 'fake_capture_$_captureCount.jpg');
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
    _analysisTimer?.cancel();
  }
}
