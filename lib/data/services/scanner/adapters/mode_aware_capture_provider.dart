import 'package:flutter/widgets.dart';

import '../../../../domain/models/capture_models.dart';
import '../../../../domain/models/provider_info.dart';
import '../../../../domain/providers/capture_provider.dart';
import '../live_preview_source.dart';

/// Routes document capture to the native document-scanner fallback
/// (SPEC 9.6) and book capture to a live camera still pipeline so spreads
/// can be split and dewarped in-app.
class ModeAwareCaptureProvider
    implements CaptureProvider, LivePreviewSource, BatchDocumentCapture {
  ModeAwareCaptureProvider({
    required CaptureProvider document,
    required CaptureProvider book,
  }) : _document = document,
       _book = book,
       _active = document;

  final CaptureProvider _document;
  final CaptureProvider _book;
  CaptureProvider _active;

  @override
  ProviderInfo get info => _active.info;

  @override
  int? get previewTextureId => _active.previewTextureId;

  @override
  double get previewAspectRatio => _active.previewAspectRatio;

  @override
  Widget? buildLivePreview() {
    final active = _active;
    if (active is LivePreviewSource) {
      return (active as LivePreviewSource).buildLivePreview();
    }
    return null;
  }

  @override
  Future<ScannerCapabilities> capabilities() => _active.capabilities();

  @override
  Future<void> openSession(CaptureMode mode) async {
    final next = mode == CaptureMode.bookSpread ? _book : _document;
    if (!identical(next, _active)) {
      await _active.closeSession();
      _active = next;
    }
    await _active.openSession(mode);
  }

  @override
  Stream<FrameAnalysis> analysisStream() => _active.analysisStream();

  @override
  Future<StillCapture> captureStill({bool bypassQualityGate = false}) =>
      _active.captureStill(bypassQualityGate: bypassQualityGate);

  @override
  Future<List<StillCapture>> scanDocuments({int maxPages = 50}) async {
    final active = _active;
    if (active is BatchDocumentCapture) {
      return (active as BatchDocumentCapture).scanDocuments(maxPages: maxPages);
    }
    return [await active.captureStill()];
  }

  @override
  Future<void> setFlashMode(FlashMode mode) => _active.setFlashMode(mode);

  @override
  Future<void> setZoom(double level) => _active.setZoom(level);

  @override
  Future<void> setFocusAndExposurePoint(double x, double y) =>
      _active.setFocusAndExposurePoint(x, y);

  @override
  Future<void> closeSession() => _active.closeSession();
}
