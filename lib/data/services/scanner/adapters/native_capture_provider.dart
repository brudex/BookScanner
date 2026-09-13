import '../../../../domain/models/capture_models.dart';
import '../../../../domain/models/provider_info.dart';
import '../../../../domain/providers/capture_provider.dart';
import '../scanner_platform_channel.dart';

/// Adapter converting the platform-neutral [ScannerPlatformChannel] into the
/// [CaptureProvider] contract. Selected by the composition layer on Android
/// (backed by Kotlin/CameraX) and iOS (backed by Swift/AVFoundation) — the
/// two native implementations return identical shapes over the channel so
/// this single adapter serves both platforms (SPEC 9.1: "same page, crop,
/// quality, warning, and processing-state models").
class NativeCaptureProvider implements CaptureProvider {
  NativeCaptureProvider(this._channel, {required String platformLabel})
    : _providerName = 'native-capture-$platformLabel';

  final ScannerPlatformChannel _channel;
  final String _providerName;

  int? _previewTextureId;

  @override
  int? get previewTextureId => _previewTextureId;

  double _previewAspectRatio = 4 / 3;

  @override
  double get previewAspectRatio => _previewAspectRatio;

  @override
  ProviderInfo get info =>
      ProviderInfo(providerName: _providerName, adapterVersion: '2.0.0');

  @override
  Future<ScannerCapabilities> capabilities() => _channel.capabilities();

  @override
  Future<void> openSession(CaptureMode mode) async {
    final session = await _channel.openSession(mode);
    _previewTextureId = session.textureId;
    _previewAspectRatio = session.previewAspectRatio;
  }

  @override
  Stream<FrameAnalysis> analysisStream() => _channel.analysisStream();

  @override
  Future<StillCapture> captureStill({bool bypassQualityGate = false}) =>
      _channel.captureStill();

  @override
  Future<void> setFlashMode(FlashMode mode) => _channel.setFlashMode(mode);

  @override
  Future<void> setZoom(double level) => _channel.setZoom(level);

  @override
  Future<void> setFocusAndExposurePoint(double x, double y) =>
      _channel.setFocusAndExposurePoint(x, y);

  @override
  Future<void> closeSession() async {
    await _channel.closeSession();
    _previewTextureId = null;
  }
}
