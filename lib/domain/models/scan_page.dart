import 'capture_models.dart';
import 'geometry.dart';
import 'provider_info.dart';

enum PageStatus { capturing, processing, ready, needsRescan, error }

enum PageFilter { original, enhancedColor, grayscale, blackAndWhite, photo }

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
/// user explicitly deletes it (SPEC 6.2 "Page-level undo and access to the
/// original image until the user deletes it").
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
    this.filter = PageFilter.original,
    this.brightness = 0,
    this.contrast = 0,
    this.sharpness = 0,
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
  final PageFilter filter;
  final double brightness;
  final double contrast;
  final double sharpness;

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
    PageFilter? filter,
    double? brightness,
    double? contrast,
    double? sharpness,
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
    filter: filter ?? this.filter,
    brightness: brightness ?? this.brightness,
    contrast: contrast ?? this.contrast,
    sharpness: sharpness ?? this.sharpness,
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
