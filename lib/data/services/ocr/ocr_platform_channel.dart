import 'package:flutter/services.dart';

import '../../../domain/models/ocr_block.dart';
import '../../../domain/models/provider_info.dart';
import 'ocr_channel_contract.dart';

/// Thin Service wrapper around the native OCR platform channel (SPEC 9.1/9.7:
/// treat the platform-channel wrapper as a Service; Flutter code must not
/// import ML Kit/Vision types directly). Nothing outside
/// `data/services/ocr/` may import `package:flutter/services.dart` channel
/// types for OCR.
class OcrPlatformChannel {
  OcrPlatformChannel({MethodChannel? methodChannel})
    : _methodChannel =
          methodChannel ??
          const MethodChannel(OcrChannelContract.methodChannelName);

  final MethodChannel _methodChannel;

  Future<T> _invoke<T>(String method, [Map<String, Object?>? args]) async {
    try {
      final result = await _methodChannel.invokeMethod<T>(method, args);
      if (result == null) {
        throw const ProviderException(
          ProviderErrorCategory.unknown,
          'Null result from native OCR channel',
        );
      }
      return result;
    } on PlatformException catch (e) {
      throw ProviderException(
        _categoryFor(e.code),
        e.message ?? 'Native OCR error',
        diagnosticCode: e.code,
        providerName: 'native-ocr-channel',
      );
    } on MissingPluginException {
      throw const ProviderException(
        ProviderErrorCategory.unsupportedDevice,
        'Native OCR plugin is not registered on this platform',
        providerName: 'native-ocr-channel',
      );
    }
  }

  static ProviderErrorCategory _categoryFor(String code) => switch (code) {
    OcrChannelContract.errorUnsupportedDevice =>
      ProviderErrorCategory.unsupportedDevice,
    OcrChannelContract.errorModelUnavailable =>
      ProviderErrorCategory.modelUnavailable,
    OcrChannelContract.errorProcessingFailed =>
      ProviderErrorCategory.processingFailed,
    OcrChannelContract.errorStorageUnavailable =>
      ProviderErrorCategory.storageUnavailable,
    _ => ProviderErrorCategory.unknown,
  };

  Future<Set<String>> supportedLanguages() async {
    final list = await _invoke<List<Object?>>(
      OcrChannelContract.methodSupportedLanguages,
    );
    return list.cast<String>().toSet();
  }

  /// Returns raw lines (see class doc on [OcrChannelContract]) as
  /// [OcrBlock]s with `blockType = BlockType.unknown`, `readingOrder` equal
  /// to the raw provider index, and `pageId` left empty — the caller
  /// ([RunOcrUseCase] via [AnalyzeOcrLayoutUseCase]) fills in real values.
  Future<List<OcrBlock>> recognize({
    required String imagePath,
    required List<String> languages,
    required String mode,
  }) async {
    final map = await _invoke<Map<Object?, Object?>>(
      OcrChannelContract.methodRecognize,
      {
        'imagePath': imagePath,
        'languages': languages,
        'mode': mode,
        'contractVersion': OcrChannelContract.contractVersion,
      },
    );
    final rawLines = (map['lines'] as List).cast<Map<Object?, Object?>>();
    return [
      for (var i = 0; i < rawLines.length; i++)
        _blockFromChannel(rawLines[i], i),
    ];
  }

  static OcrBlock _blockFromChannel(Map<Object?, Object?> raw, int index) {
    final wordsRaw = (raw['words'] as List? ?? const [])
        .cast<Map<Object?, Object?>>();
    return OcrBlock(
      id: '',
      pageId: '',
      boundingPolygon: Polygon.fromJson(
        (raw['boundingPolygon']! as Map).cast<String, Object?>(),
      ),
      text: raw['text']! as String,
      confidence: (raw['confidence']! as num).toDouble(),
      language: raw['language'] as String? ?? '',
      blockType: BlockType.unknown,
      readingOrder: index,
      words: [
        for (final w in wordsRaw)
          OcrWord(
            text: w['text']! as String,
            boundingPolygon: Polygon.fromJson(
              (w['boundingPolygon']! as Map).cast<String, Object?>(),
            ),
            confidence: (w['confidence']! as num).toDouble(),
          ),
      ],
    );
  }
}
