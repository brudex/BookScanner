import 'package:uuid/uuid.dart';

import '../models/capture_models.dart';
import '../models/geometry.dart';
import '../models/scan_page.dart';
import '../providers/image_enhancement_provider.dart';
import '../providers/page_detection_provider.dart';
import '../repositories/page_path_allocator.dart';
import '../repositories/page_repository.dart';

/// Coordinates the post-shutter pipeline: persist the original still,
/// then crop/perspective-correct/enhance in one decode. This is the
/// single place that turns a raw [StillCapture] into a durable
/// [ScanPage] so both the document and book capture flows share identical
/// persistence and crash-safety behavior (SPEC 9.2: "Persist the original
/// still image immediately... Enhancement... run as cancellable background
/// jobs").
///
/// Page finding runs inside [ImageEnhancementProvider.enhance] when
/// `detectCrop: true` so the JPEG is decoded once. A detection miss
/// degrades to the capture-time hint or [Quad.fullFrame] (SPEC 9.7)
/// without aborting the capture.
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
    PageFilter filter = PageFilter.original,
  }) async {
    final pageId = _uuid.v4();

    final outputPath = _paths.processedPathFor(pageId, ext: 'jpg');
    final enhancement = await _enhancementProvider.enhance(
      EnhancementRequest(
        sourceImagePath: capture.originalImagePath,
        outputImagePath: outputPath,
        cropPoints: capture.detectedQuad ?? Quad.fullFrame,
        rotationDegrees: 0,
        filter: filter,
        detectCrop: true,
      ),
    );
    final quad = enhancement.cropPoints;

    final now = DateTime.now().millisecondsSinceEpoch;
    final page = ScanPage(
      id: pageId,
      projectId: projectId,
      sequence: sequence,
      originalImagePath: capture.originalImagePath,
      processedImagePath: enhancement.processedImagePath,
      thumbnailPath: enhancement.thumbnailPath,
      cropPoints: quad,
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

  /// Re-runs crop/rotation/filter/enhancement for an existing page (manual
  /// corner adjustment, filter change) without re-capturing (SPEC 6.2:
  /// "Page-level undo and access to the original image until the user
  /// deletes it").
  Future<ScanPage> reprocessPage(
    ScanPage page, {
    Quad? cropPoints,
    int? rotationDegrees,
    PageFilter? filter,
    double? brightness,
    double? contrast,
    double? sharpness,
  }) async {
    final outputPath = _paths.processedPathFor(page.id, ext: 'jpg');
    final enhancement = await _enhancementProvider.enhance(
      EnhancementRequest(
        sourceImagePath: page.originalImagePath,
        outputImagePath: outputPath,
        cropPoints: cropPoints ?? page.cropPoints ?? Quad.fullFrame,
        rotationDegrees: rotationDegrees ?? page.rotationDegrees,
        filter: filter ?? page.filter,
        brightness: brightness ?? page.brightness,
        contrast: contrast ?? page.contrast,
        sharpness: sharpness ?? page.sharpness,
      ),
    );

    final updated = page.copyWith(
      processedImagePath: enhancement.processedImagePath,
      thumbnailPath: enhancement.thumbnailPath,
      cropPoints: cropPoints,
      rotationDegrees: rotationDegrees,
      filter: filter,
      brightness: brightness,
      contrast: contrast,
      sharpness: sharpness,
      qualityScore: enhancement.qualityScore,
      status: enhancement.qualityScore < 0.35
          ? PageStatus.needsRescan
          : PageStatus.ready,
    );
    await _pageRepository.updatePage(updated);
    return updated;
  }

  /// Replaces [pageId]'s image content in place with a freshly captured
  /// [capture] (the "Rescan" action, SPEC 6.3) — as opposed to
  /// [processCapture], which always allocates a brand-new page. Runs the
  /// same detect/enhance pipeline `processCapture` does, but keeps the
  /// page's existing identity (`id`/`sequence`/`logicalPageLabel`/
  /// `spreadSiblingPageId`) and its existing filter/brightness/contrast/
  /// sharpness settings rather than resetting them.
  ///
  /// `originalImagePath` is intentionally *not* reachable through
  /// [ScanPage.copyWith] (that method preserves it unconditionally, by
  /// design — SPEC 6.2's "access to the original image until the user
  /// deletes it" treats it as otherwise immutable) — a genuine rescan is the
  /// one deliberate exception, so this constructs a new [ScanPage] directly.
  ///
  /// Known follow-up, not fixed here: any OCR blocks already persisted for
  /// this `pageId` now describe the *old* image's text and are not
  /// automatically invalidated or re-run.
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
        detectCrop: true,
      ),
    );
    final quad = enhancement.cropPoints;

    final now = DateTime.now().millisecondsSinceEpoch;
    final replaced = ScanPage(
      id: existing.id,
      projectId: existing.projectId,
      sequence: existing.sequence,
      logicalPageLabel: existing.logicalPageLabel,
      originalImagePath: capture.originalImagePath,
      processedImagePath: enhancement.processedImagePath,
      thumbnailPath: enhancement.thumbnailPath,
      cropPoints: quad,
      filter: existing.filter,
      brightness: existing.brightness,
      contrast: existing.contrast,
      sharpness: existing.sharpness,
      qualityScore: enhancement.qualityScore,
      warnings: capture.warnings,
      // Genuinely new pixel content -- any prior duplicate/missing-page
      // flags are stale until DetectPageAnomaliesUseCase re-evaluates the
      // project.
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
