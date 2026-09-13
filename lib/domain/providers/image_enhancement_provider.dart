import '../models/geometry.dart';
import '../models/provider_info.dart';
import '../models/scan_page.dart';

class EnhancementRequest {
  const EnhancementRequest({
    required this.sourceImagePath,
    required this.outputImagePath,
    required this.cropPoints,
    required this.rotationDegrees,
    required this.filter,
    this.brightness = 0,
    this.contrast = 0,
    this.sharpness = 0,
    this.removeShadowsAndStains = true,
    this.detectCrop = false,
    this.splitOpenBook = true,
  });

  final String sourceImagePath;
  final String outputImagePath;
  final Quad cropPoints;
  final int rotationDegrees;
  final PageFilter filter;
  final double brightness;
  final double contrast;
  final double sharpness;
  final bool removeShadowsAndStains;

  /// When true, the adapter re-detects the page on the decoded still and
  /// uses that quad (falling back to [cropPoints] if detection returns
  /// null). Capture uses this so detect+enhance share one JPEG decode.
  final bool detectCrop;

  /// When [detectCrop] is true, split an open-book paper blob at the
  /// gutter and keep the page closest to frame center. Book-spread halves
  /// are already one page, so they pass false.
  final bool splitOpenBook;
}

class EnhancementResult {
  const EnhancementResult({
    required this.processedImagePath,
    required this.thumbnailPath,
    required this.qualityScore,
    required this.providerInfo,
    this.cropPoints = Quad.fullFrame,
  });

  final String processedImagePath;
  final String thumbnailPath;
  final double qualityScore;
  final ProviderInfo providerInfo;

  /// The quad actually applied (detected when [EnhancementRequest.detectCrop]
  /// was true, otherwise the request's [EnhancementRequest.cropPoints]).
  final Quad cropPoints;
}

/// Crop/perspective correction, rotation, filters, and shadow/stain/noise
/// cleanup (SPEC 6.2). Cleanup must never erase printed content; when
/// confidence in a cleanup region is low the original pixels are preserved.
abstract interface class ImageEnhancementProvider {
  ProviderInfo get info;

  Future<EnhancementResult> enhance(EnhancementRequest request);

  /// Cheap 0.0-1.0 sharpness/exposure/coverage quality estimate, used both
  /// live and on saved pages to flag pages for rescan.
  Future<double> scoreQuality(String imagePath);
}
