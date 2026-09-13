import '../models/geometry.dart';
import '../models/provider_info.dart';

class SpreadSplitResult {
  const SpreadSplitResult({
    required this.leftPageImagePath,
    required this.rightPageImagePath,
    required this.providerInfo,
    required this.confidence,
  });

  final String leftPageImagePath;
  final String rightPageImagePath;

  /// 0.0-1.0 confidence the split boundary (gutter) was located correctly.
  final double confidence;
  final ProviderInfo providerInfo;
}

class DewarpResult {
  const DewarpResult({
    required this.flattenedImagePath,
    required this.providerInfo,
    required this.occlusionDetected,
    required this.occlusionHighConfidenceTextLoss,
  });

  final String flattenedImagePath;
  final ProviderInfo providerInfo;

  /// True if a finger/hand/occlusion was detected anywhere on the page.
  final bool occlusionDetected;

  /// True only if the occlusion sits over high-confidence text region with
  /// low reconstruction confidence — this must trigger a rescan
  /// recommendation, never silent pixel invention (SPEC 9.3).
  final bool occlusionHighConfidenceTextLoss;
}

/// Book-specific segmentation/dewarping pipeline (SPEC 9.3). Two-page
/// splitting, curve flattening, and finger removal are independent,
/// versioned, user-correctable stages.
abstract interface class BookDewarpProvider {
  ProviderInfo get info;

  Future<bool> isSupported();

  /// Splits a two-page spread photo into two standalone page images. Auto-
  /// detects the gutter position unless [gutterXOverride] (0.0-1.0,
  /// normalized to the source image width) is given, in which case the
  /// provider splits at that explicit position instead — used for manual
  /// split correction (SPEC 5.2 acceptance criterion: "the user can correct
  /// the split") and always reports full confidence since the position was
  /// user-specified, not detected.
  Future<SpreadSplitResult> splitSpread(
    String spreadImagePath, {
    double? gutterXOverride,
  });

  /// Flattens one already-split page. When [outputPath] is set, the
  /// dewarped JPEG is written there (durable processed storage). When
  /// omitted, the adapter must still persist outside `tmpDir`.
  Future<DewarpResult> dewarp(
    String pageImagePath,
    Quad pageBounds, {
    String? outputPath,
  });
}
