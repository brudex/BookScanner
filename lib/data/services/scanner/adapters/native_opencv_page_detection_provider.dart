import '../../../../domain/models/capture_models.dart';
import '../../../../domain/models/geometry.dart';
import '../../../../domain/models/provider_info.dart';
import '../../../../domain/providers/page_detection_provider.dart';
import '../vision_platform_channel.dart';
import 'dart_page_detection_provider.dart';

/// Native OpenCV still detector with a Dart contour fallback when the
/// vision plugin is missing or reports unavailable.
class NativeOpenCvPageDetectionProvider implements PageDetectionProvider {
  NativeOpenCvPageDetectionProvider(
    this._channel, {
    PageDetectionProvider? fallback,
  }) : _fallback = fallback ?? DartPageDetectionProvider();

  final VisionPlatformChannel _channel;
  final PageDetectionProvider _fallback;

  @override
  ProviderInfo get info => const ProviderInfo(
    providerName: 'native-opencv-detection',
    adapterVersion: '1.0.0',
  );

  @override
  Future<Quad?> detectQuad(String imagePath) async {
    try {
      final availability = await _channel.isAvailable();
      if (!availability.available) {
        return _fallback.detectQuad(imagePath);
      }
      final result = await _channel.detectStill(imagePath);
      if (result.confidence < DetectionThresholds.minConfidence) {
        return null;
      }
      return result.quad;
    } on Object {
      return _fallback.detectQuad(imagePath);
    }
  }
}
