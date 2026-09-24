import 'capture_models.dart';
import 'geometry.dart';
import 'provider_info.dart';

enum PageStatus { capturing, processing, ready, needsRescan, error }

enum PageFilter { original, enhancedColor, grayscale, blackAndWhite, photo }

/// Default look for newly captured pages: enhanced/document color — the
/// industry-standard scanner look (whitish paper, stronger contrast, light
/// color kept). Not hard B&W; users can still pick B&W in adjust.
///
/// The raw camera still is retained for future crop/filter (SPEC 6.2);
/// library/review show [ScanPage.processedImagePath] until the user opens
/// an edit surface (crop uses the original).
const PageFilter kDefaultCaptureFilter = PageFilter.enhancedColor;

/// Pipeline stages tracked independently per SPEC 9.5: "Each pipeline stage
/// stores its version and output. Changing a crop or filter invalidates only
/// dependent stages."
enum PipelineStage { detection, crop, split, dewarp, enhancement, ocr }

/// Version + provider identity recorded for one pipeline stage output, so a
/// provider swap can invalidate and regenerate only dependent stages.
class StageRecord {
  const StageRecord({
    required this.version,
    required this.providerInfo,
    required this.completedAtMs,
  });

  final int version;
  final ProviderInfo providerInfo;
  final int completedAtMs;
}

/// A single scanned page (SPEC 10). Original image is retained until the
/// user explicitly deletes it (SPEC 6.2) so crop/filter can re-derive from
/// the camera still; UI surfaces show [processedImagePath] by default.
class ScanPage {
  const ScanPage({
    required this.id,
    required this.projectId,
    required this.sequence,
    required this.originalImagePath,
    required this.status,
    this.logicalPageLabel,
    this.processedImagePath,
    this.thumbnailPath,
    this.cropPoints,
    this.rotationDegrees = 0,
    this.fineRotationDegrees = 0,
    this.filter = PageFilter.original,
    this.brightness = 0,
    this.contrast = 0,
    this.sharpness = 0,
    this.threshold = 0.5,
    this.qualityScore,
    this.warnings = const {},
    this.duplicateOfPageId,
    this.likelyMissingBefore = false,
    this.dismissedWarnings = const {},
    this.stages = const {},
    this.capturedAtMs,
    this.spreadSiblingPageId,
  });

  final String id;
  final String projectId;

  /// Position within [Project.pageOrder]. Kept denormalized for fast sort
  /// queries; [Project.pageOrder] remains the authoritative order.
  final int sequence;

  /// User-facing label: printed page number, roman numeral, "Cover", etc.
  /// Null means unnumbered.
  final String? logicalPageLabel;

  final String originalImagePath;
  final String? processedImagePath;
  final String? thumbnailPath;

  final Quad? cropPoints;
  final int rotationDegrees;

  /// Additional arbitrary-angle rotation (-45..45 degrees), applied after
  /// the 90-degree-increment [rotationDegrees] (SPEC 6.2 fine rotation).
  final double fineRotationDegrees;
  final PageFilter filter;
  final double brightness;
  final double contrast;
  final double sharpness;

  /// Binarization cutoff (0.0-1.0) used only by [PageFilter.blackAndWhite]
  /// (SPEC 6.2 "adjustable... threshold").
  final double threshold;

  /// 0.0-1.0; null until quality analysis completes.
  final double? qualityScore;
  final Set<QualityWarning> warnings;

  final String? duplicateOfPageId;
  final bool likelyMissingBefore;
  final Set<String> dismissedWarnings;

  final Map<PipelineStage, StageRecord> stages;
  final int? capturedAtMs;

  /// Set when this page was produced by splitting a two-page book spread;
  /// points at the other half.
  final String? spreadSiblingPageId;

  final PageStatus status;

  bool get needsReview =>
      warnings.isNotEmpty &&
      warnings
          .difference(dismissedWarnings.map(_warningFromName).toSet())
          .isNotEmpty;

  /// True when a distinct raw camera file still exists separately from the
  /// baked scan. After enhance, both paths usually match and revert is a no-op.
  bool get hasDistinctOriginal =>
      processedImagePath != null &&
      processedImagePath!.isNotEmpty &&
      processedImagePath != originalImagePath;

  static QualityWarning _warningFromName(String name) =>
      QualityWarning.values.byName(name);

  ScanPage copyWith({
    int? sequence,
    String? logicalPageLabel,
    bool? clearLogicalPageLabel,
    String? processedImagePath,
    String? thumbnailPath,
    Quad? cropPoints,
    int? rotationDegrees,
    double? fineRotationDegrees,
    PageFilter? filter,
    double? brightness,
    double? contrast,
    double? sharpness,
    double? threshold,
    double? qualityScore,
    Set<QualityWarning>? warnings,
    String? duplicateOfPageId,
    bool? clearDuplicateOfPageId,
    bool? likelyMissingBefore,
    Set<String>? dismissedWarnings,
    Map<PipelineStage, StageRecord>? stages,
    PageStatus? status,
    String? spreadSiblingPageId,
  }) => ScanPage(
    id: id,
    projectId: projectId,
    sequence: sequence ?? this.sequence,
    logicalPageLabel: (clearLogicalPageLabel ?? false)
        ? null
        : (logicalPageLabel ?? this.logicalPageLabel),
    originalImagePath: originalImagePath,
    processedImagePath: processedImagePath ?? this.processedImagePath,
    thumbnailPath: thumbnailPath ?? this.thumbnailPath,
    cropPoints: cropPoints ?? this.cropPoints,
    rotationDegrees: rotationDegrees ?? this.rotationDegrees,
    fineRotationDegrees: fineRotationDegrees ?? this.fineRotationDegrees,
    filter: filter ?? this.filter,
    brightness: brightness ?? this.brightness,
    contrast: contrast ?? this.contrast,
    sharpness: sharpness ?? this.sharpness,
    threshold: threshold ?? this.threshold,
    qualityScore: qualityScore ?? this.qualityScore,
    warnings: warnings ?? this.warnings,
    duplicateOfPageId: (clearDuplicateOfPageId ?? false)
        ? null
        : (duplicateOfPageId ?? this.duplicateOfPageId),
    likelyMissingBefore: likelyMissingBefore ?? this.likelyMissingBefore,
    dismissedWarnings: dismissedWarnings ?? this.dismissedWarnings,
    stages: stages ?? this.stages,
    capturedAtMs: capturedAtMs,
    spreadSiblingPageId: spreadSiblingPageId ?? this.spreadSiblingPageId,
    status: status ?? this.status,
  );
}
