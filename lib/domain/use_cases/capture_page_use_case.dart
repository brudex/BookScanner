import 'package:uuid/uuid.dart';

import '../models/capture_models.dart';
import '../models/geometry.dart';
import '../models/scan_page.dart';
import '../providers/image_enhancement_provider.dart';
import '../providers/page_detection_provider.dart';
import '../repositories/page_path_allocator.dart';
import '../repositories/page_repository.dart';

/// Coordinates the post-shutter pipeline: persist the original still, then
/// crop/perspective-correct/enhance. Industry-standard retention: the raw
/// camera file stays on disk for future crop/filter (SPEC 6.2) while the UI
/// shows [ScanPage.processedImagePath] everywhere except edit surfaces.
class CapturePageUseCase {
  CapturePageUseCase({
    required PageRepository pageRepository,
    required ImageEnhancementProvider enhancementProvider,
    required PageDetectionProvider detectionProvider,
    required PagePathAllocator fileStorage,
    Uuid? uuid,
  }) : _pageRepository = pageRepository,
       _enhancementProvider = enhancementProvider,
       _detectionProvider = detectionProvider,
       _paths = fileStorage,
       _uuid = uuid ?? const Uuid();

  final PageRepository _pageRepository;
  final ImageEnhancementProvider _enhancementProvider;
  final PageDetectionProvider _detectionProvider;
  final PagePathAllocator _paths;
  final Uuid _uuid;

  Future<ScanPage> processCapture({
    required StillCapture capture,
    required String projectId,
    required int sequence,
    PageFilter filter = kDefaultCaptureFilter,

    /// When true, the page is stored as the imported file. No crop, document
    /// filter, or OCR-style enhancement — used for PDF and file import so a
    /// merge keeps the original pages.
    bool keepOriginal = false,
  }) async {
    final pageId = _uuid.v4();
    final appliedFilter = keepOriginal ? PageFilter.original : filter;
    final passthrough = keepOriginal || capture.nativeReady;

    final outputPath = _paths.processedPathFor(
      pageId,
      ext: passthrough ? _sourceExt(capture.originalImagePath) : 'jpg',
    );
    final enhancement = await _enhancementProvider.enhance(
      EnhancementRequest(
        sourceImagePath: capture.originalImagePath,
        outputImagePath: outputPath,
        cropPoints: capture.detectedQuad ?? Quad.fullFrame,
        rotationDegrees: 0,
        filter: appliedFilter,
        detectCrop: !passthrough,
        passthrough: passthrough,
        removeShadowsAndStains: !passthrough,
      ),
    );

    final now = DateTime.now().millisecondsSinceEpoch;
    final page = ScanPage(
      id: pageId,
      projectId: projectId,
      sequence: sequence,
      originalImagePath: capture.originalImagePath,
      processedImagePath: enhancement.processedImagePath,
      thumbnailPath: enhancement.thumbnailPath,
      cropPoints: enhancement.cropPoints,
      filter: appliedFilter,
      qualityScore: enhancement.qualityScore,
      warnings: capture.warnings,
      capturedAtMs: capture.capturedAtMs,
      status: enhancement.qualityScore < 0.35
          ? PageStatus.needsRescan
          : PageStatus.ready,
      stages: {
        PipelineStage.detection: StageRecord(
          version: 1,
          providerInfo: _detectionProvider.info,
          completedAtMs: now,
        ),
        PipelineStage.enhancement: StageRecord(
          version: 1,
          providerInfo: enhancement.providerInfo,
          completedAtMs: now,
        ),
      },
    );

    await _pageRepository.addPage(page);
    return page;
  }

  /// Stores the shutter photo and returns. Crop and filters happen page by
  /// page after the user taps Done, not on Review.
  Future<ScanPage> saveShot({
    required StillCapture capture,
    required String projectId,
    required int sequence,
  }) async {
    final page = ScanPage(
      id: _uuid.v4(),
      projectId: projectId,
      sequence: sequence,
      originalImagePath: capture.originalImagePath,
      processedImagePath: capture.originalImagePath,
      thumbnailPath: capture.originalImagePath,
      cropPoints: Quad.fullFrame,
      filter: PageFilter.original,
      qualityScore: capture.qualityScore,
      warnings: capture.warnings,
      capturedAtMs: capture.capturedAtMs,
      status: PageStatus.ready,
    );
    await _pageRepository.addPage(page);
    return page;
  }

  /// Re-runs crop/rotation/filter/enhancement from the retained original
  /// (SPEC 6.2). Does not delete the camera still.
  Future<ScanPage> reprocessPage(
    ScanPage page, {
    Quad? cropPoints,
    int? rotationDegrees,
    double? fineRotationDegrees,
    PageFilter? filter,
    double? brightness,
    double? contrast,
    double? sharpness,
    double? threshold,
  }) async {
    final resolvedCrop = cropPoints ?? page.cropPoints ?? Quad.fullFrame;
    final outputPath = _paths.processedPathFor(page.id, ext: 'jpg');
    final enhancement = await _enhancementProvider.enhance(
      EnhancementRequest(
        sourceImagePath: page.originalImagePath,
        outputImagePath: outputPath,
        cropPoints: resolvedCrop,
        rotationDegrees: rotationDegrees ?? page.rotationDegrees,
        filter: filter ?? page.filter,
        fineRotationDegrees: fineRotationDegrees ?? page.fineRotationDegrees,
        brightness: brightness ?? page.brightness,
        contrast: contrast ?? page.contrast,
        sharpness: sharpness ?? page.sharpness,
        threshold: threshold ?? page.threshold,
      ),
    );

    final updated = page.copyWith(
      processedImagePath: enhancement.processedImagePath,
      thumbnailPath: enhancement.thumbnailPath,
      cropPoints: resolvedCrop,
      rotationDegrees: rotationDegrees ?? page.rotationDegrees,
      fineRotationDegrees: fineRotationDegrees ?? page.fineRotationDegrees,
      filter: filter ?? page.filter,
      brightness: brightness ?? page.brightness,
      contrast: contrast ?? page.contrast,
      sharpness: sharpness ?? page.sharpness,
      threshold: threshold ?? page.threshold,
      qualityScore: enhancement.qualityScore,
      status: enhancement.qualityScore < 0.35
          ? PageStatus.needsRescan
          : PageStatus.ready,
    );
    await _pageRepository.updatePage(updated);
    return updated;
  }

  /// Renders a filter/crop preview JPEG without updating the page row.
  Future<String> renderAdjustedPreview(
    ScanPage page, {
    Quad? cropPoints,
    int? rotationDegrees,
    double? fineRotationDegrees,
    PageFilter? filter,
    double? brightness,
    double? contrast,
    double? sharpness,
    double? threshold,
  }) async {
    final resolvedCrop = cropPoints ?? page.cropPoints ?? Quad.fullFrame;
    final outputPath = _paths.processedPathFor('${page.id}_preview', ext: 'jpg');
    final enhancement = await _enhancementProvider.enhance(
      EnhancementRequest(
        sourceImagePath: page.originalImagePath,
        outputImagePath: outputPath,
        cropPoints: resolvedCrop,
        rotationDegrees: rotationDegrees ?? page.rotationDegrees,
        filter: filter ?? page.filter,
        fineRotationDegrees: fineRotationDegrees ?? page.fineRotationDegrees,
        brightness: brightness ?? page.brightness,
        contrast: contrast ?? page.contrast,
        sharpness: sharpness ?? page.sharpness,
        threshold: threshold ?? page.threshold,
      ),
    );
    return enhancement.processedImagePath;
  }

  /// Rescan: replace image content in place; keeps page identity and filter
  /// settings. New camera still becomes the retained original.
  Future<ScanPage> replacePage(String pageId, StillCapture capture) async {
    final existing = await _pageRepository.getPage(pageId);
    if (existing == null) {
      throw StateError('Page not found: $pageId');
    }

    final outputPath = _paths.processedPathFor(pageId, ext: 'jpg');
    final enhancement = await _enhancementProvider.enhance(
      EnhancementRequest(
        sourceImagePath: capture.originalImagePath,
        outputImagePath: outputPath,
        cropPoints: capture.detectedQuad ?? Quad.fullFrame,
        rotationDegrees: 0,
        filter: existing.filter,
        brightness: existing.brightness,
        contrast: existing.contrast,
        sharpness: existing.sharpness,
        detectCrop: !capture.nativeReady,
        passthrough: capture.nativeReady,
      ),
    );

    final now = DateTime.now().millisecondsSinceEpoch;
    final replaced = ScanPage(
      id: existing.id,
      projectId: existing.projectId,
      sequence: existing.sequence,
      logicalPageLabel: existing.logicalPageLabel,
      originalImagePath: capture.originalImagePath,
      processedImagePath: enhancement.processedImagePath,
      thumbnailPath: enhancement.thumbnailPath,
      cropPoints: enhancement.cropPoints,
      filter: existing.filter,
      brightness: existing.brightness,
      contrast: existing.contrast,
      sharpness: existing.sharpness,
      qualityScore: enhancement.qualityScore,
      warnings: capture.warnings,
      stages: {
        PipelineStage.detection: StageRecord(
          version: 1,
          providerInfo: _detectionProvider.info,
          completedAtMs: now,
        ),
        PipelineStage.enhancement: StageRecord(
          version: 1,
          providerInfo: enhancement.providerInfo,
          completedAtMs: now,
        ),
      },
      capturedAtMs: capture.capturedAtMs,
      spreadSiblingPageId: existing.spreadSiblingPageId,
      status: enhancement.qualityScore < 0.35
          ? PageStatus.needsRescan
          : PageStatus.ready,
    );

    await _pageRepository.updatePage(replaced);
    return replaced;
  }
}

String _sourceExt(String path) {
  final slash = path.lastIndexOf('/');
  final dot = path.lastIndexOf('.');
  if (dot <= slash || dot == path.length - 1) return 'jpg';
  return path.substring(dot + 1).toLowerCase();
}
