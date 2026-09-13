import '../models/ocr_block.dart';
import '../models/provider_info.dart';

enum OcrAccuracyMode {
  /// Fast, lower-accuracy recognition for live capture guidance only.
  fast,

  /// Full accuracy path for saved pages.
  accurate,
}

class OcrRequest {
  const OcrRequest({
    required this.imagePath,
    required this.languages,
    this.mode = OcrAccuracyMode.accurate,
  });

  final String imagePath;

  /// BCP-47 language tags; OCR runs after geometric correction (SPEC 9.4).
  final List<String> languages;
  final OcrAccuracyMode mode;
}

class OcrResult {
  const OcrResult({required this.blocks, required this.providerInfo});

  /// Raw recognition output normalized into the canonical block model, with
  /// [OcrBlock.blockType] left as [BlockType.unknown] and [OcrBlock.readingOrder]
  /// in raw provider order. A separate layout-analysis use case reclassifies
  /// block types and reading order (SPEC 9.4: "Platform OCR output must not
  /// be assumed to reconstruct a book automatically").
  final List<OcrBlock> blocks;
  final ProviderInfo providerInfo;
}

/// On-device or cloud text recognition (SPEC 9.4). MVP implementations wrap
/// Apple Vision (iOS) and ML Kit Text Recognition v2 (Android); a cloud
/// adapter may be added later behind the same contract with explicit opt-in.
abstract interface class OcrProvider {
  ProviderInfo get info;

  Future<Set<String>> supportedLanguages();

  bool get requiresNetwork;

  Future<OcrResult> recognize(OcrRequest request);
}
