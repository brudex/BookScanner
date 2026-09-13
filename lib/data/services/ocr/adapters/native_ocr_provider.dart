import '../../../../domain/models/provider_info.dart';
import '../../../../domain/providers/ocr_provider.dart';
import '../ocr_platform_channel.dart';

/// Adapter converting the platform-neutral [OcrPlatformChannel] into the
/// [OcrProvider] contract. Selected by the composition layer on Android
/// (backed by ML Kit Text Recognition v2) and iOS (backed by Vision's
/// `VNRecognizeTextRequest`) — both run fully on-device, so
/// [requiresNetwork] is always false for this adapter.
class NativeOcrProvider implements OcrProvider {
  NativeOcrProvider(this._channel, {required String platformLabel})
    : _providerName = 'native-ocr-$platformLabel';

  final OcrPlatformChannel _channel;
  final String _providerName;

  @override
  ProviderInfo get info =>
      ProviderInfo(providerName: _providerName, adapterVersion: '1.0.0');

  @override
  bool get requiresNetwork => false;

  @override
  Future<Set<String>> supportedLanguages() => _channel.supportedLanguages();

  @override
  Future<OcrResult> recognize(OcrRequest request) async {
    final blocks = await _channel.recognize(
      imagePath: request.imagePath,
      languages: request.languages,
      mode: request.mode.name,
    );
    return OcrResult(blocks: blocks, providerInfo: info);
  }
}
