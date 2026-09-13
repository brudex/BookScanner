import 'dart:io';

import 'package:uuid/uuid.dart';

import '../models/capture_models.dart';
import '../models/geometry.dart';
import '../models/project.dart';
import '../models/scan_page.dart';
import '../providers/book_dewarp_provider.dart';
import '../providers/image_enhancement_provider.dart';
import '../providers/page_detection_provider.dart';
import '../repositories/page_path_allocator.dart';
import '../repositories/page_repository.dart';

/// Coordinates the book-spread pipeline: split the captured two-page photo
/// into two standalone page images, then run each half through the same
/// detect/enhance stages a single-page capture goes through, plus
/// dewarp/occlusion detection (SPEC 5.2, 6.2, 9.3). Two-page splitting,
/// curve flattening, and finger-occlusion detection are independent,
/// versioned pipeline stages (`PipelineStage.split`/`.dewarp`), matching
/// [CapturePageUseCase]'s `.detection`/`.enhancement` stages for
/// single-page captures.
class ProcessBookSpreadUseCase {
  ProcessBookSpreadUseCase({
    required PageRepository pageRepository,
    required BookDewarpProvider dewarpProvider,
    required PageDetectionProvider detectionProvider,
    required ImageEnhancementProvider enhancementProvider,
    required PagePathAllocator fileStorage,
    Uuid? uuid,
  }) : _pageRepository = pageRepository,
       _dewarpProvider = dewarpProvider,
       _detectionProvider = detectionProvider,
       _enhancementProvider = enhancementProvider,
       _paths = fileStorage,
       _uuid = uuid ?? const Uuid();

  final PageRepository _pageRepository;
  final BookDewarpProvider _dewarpProvider;
  final PageDetectionProvider _detectionProvider;
  final ImageEnhancementProvider _enhancementProvider;
  final PagePathAllocator _paths;
  final Uuid _uuid;

  /// Deterministic shared storage key for the undivided two-page spread
  /// photo both sibling pages were split from — order-independent so either
  /// page id can be used to look it up (see [resplit]). The undivided
  /// photo must be retained (not just the two split halves) for manual
  /// split correction to have anything to re-split from.
  static String spreadOriginalPathFor(
    PagePathAllocator paths,
    String pageIdA,
    String pageIdB,
  ) {
    final key = ([pageIdA, pageIdB]..sort()).join('_spread_');
    return paths.originalPathFor(key, ext: 'jpg');
  }

  /// Returns both resulting pages in final reading-order sequence
  /// (respecting [pageOrderDirection]), already persisted.
  Future<List<ScanPage>> processCapture({
    required StillCapture capture,
    required String projectId,
    required int sequence,
    PageOrderDirection pageOrderDirection = PageOrderDirection.leftToRight,
  }) async {
    final leftId = _uuid.v4();
    final rightId = _uuid.v4();

    final spreadOriginalPath = spreadOriginalPathFor(_paths, leftId, rightId);
    await File(capture.originalImagePath).copy(spreadOriginalPath);

    final split = await _dewarpProvider.splitSpread(spreadOriginalPath);

    final leftPage = await _buildPage(
      pageId: leftId,
      siblingId: rightId,
      rawImagePath: split.leftPageImagePath,
      projectId: projectId,
      capturedAtMs: capture.capturedAtMs,
      splitConfidence: split.confidence,
    );
    final rightPage = await _buildPage(
      pageId: rightId,
      siblingId: leftId,
      rawImagePath: split.rightPageImagePath,
      projectId: projectId,
      capturedAtMs: capture.capturedAtMs,
      splitConfidence: split.confidence,
    );

    final orderedBySpine = pageOrderDirection == PageOrderDirection.rightToLeft
        ? [rightPage, leftPage]
        : [leftPage, rightPage];

    final finalPages = <ScanPage>[];
    for (var i = 0; i < orderedBySpine.length; i++) {
      final page = orderedBySpine[i].copyWith(sequence: sequence + i);
      await _pageRepository.addPage(page);
      finalPages.add(page);
    }
    return finalPages;
  }

  /// Re-runs the split at an explicit gutter position (0..1, normalized to
  /// the original spread image) for manual correction, then re-detects/
  /// re-enhances/re-dewarps both halves in place, preserving each page's id
  /// and sequence. [originalSpreadImagePath] is the undivided two-page
  /// photo retained by [processCapture] — locate it via
  /// [spreadOriginalPathFor] using either sibling page's id.
  Future<List<ScanPage>> resplit({
    required ScanPage leftPage,
    required ScanPage rightPage,
    required String originalSpreadImagePath,
    required double gutterX,
  }) async {
    final split = await _dewarpProvider.splitSpread(
      originalSpreadImagePath,
      gutterXOverride: gutterX,
    );

    final newLeft = await _buildPage(
      pageId: leftPage.id,
      siblingId: rightPage.id,
      rawImagePath: split.leftPageImagePath,
      projectId: leftPage.projectId,
      capturedAtMs: leftPage.capturedAtMs,
      splitConfidence: split.confidence,
    );
    final newRight = await _buildPage(
      pageId: rightPage.id,
      siblingId: leftPage.id,
      rawImagePath: split.rightPageImagePath,
      projectId: rightPage.projectId,
      capturedAtMs: rightPage.capturedAtMs,
      splitConfidence: split.confidence,
    );

    final updatedLeft = newLeft.copyWith(sequence: leftPage.sequence);
    final updatedRight = newRight.copyWith(sequence: rightPage.sequence);
    await _pageRepository.updatePage(updatedLeft);
    await _pageRepository.updatePage(updatedRight);
    return [updatedLeft, updatedRight];
  }

  Future<ScanPage> _buildPage({
    required String pageId,
    required String siblingId,
    required String rawImagePath,
    required String projectId,
    required int? capturedAtMs,
    double splitConfidence = 1,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final originalPath = _paths.originalPathFor(pageId, ext: 'jpg');
    if (rawImagePath != originalPath) {
      await File(rawImagePath).copy(originalPath);
    }

    final processedPath = _paths.processedPathFor(pageId, ext: 'jpg');
    final enhancement = await _enhancementProvider.enhance(
      EnhancementRequest(
        sourceImagePath: originalPath,
        outputImagePath: processedPath,
        cropPoints: Quad.fullFrame,
        rotationDegrees: 0,
        filter: PageFilter.original,
        detectCrop: true,
        splitOpenBook: false,
      ),
    );
    final quad = enhancement.cropPoints;

    final dewarp = await _dewarpProvider.dewarp(
      enhancement.processedImagePath,
      Quad.fullFrame,
      outputPath: processedPath,
    );

    final warnings = <QualityWarning>{
      if (dewarp.occlusionDetected) QualityWarning.fingerCovering,
    };

    return ScanPage(
      id: pageId,
      projectId: projectId,
      sequence: 0,
      originalImagePath: originalPath,
      processedImagePath: dewarp.flattenedImagePath,
      thumbnailPath: enhancement.thumbnailPath,
      cropPoints: quad,
      qualityScore: enhancement.qualityScore,
      warnings: warnings,
      spreadSiblingPageId: siblingId,
      status:
          dewarp.occlusionHighConfidenceTextLoss ||
              enhancement.qualityScore < 0.35 ||
              splitConfidence < 0.35
          ? PageStatus.needsRescan
          : PageStatus.ready,
      capturedAtMs: capturedAtMs,
      stages: {
        PipelineStage.split: StageRecord(
          version: 1,
          providerInfo: _dewarpProvider.info,
          completedAtMs: now,
        ),
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
        PipelineStage.dewarp: StageRecord(
          version: 1,
          providerInfo: dewarp.providerInfo,
          completedAtMs: now,
        ),
      },
    );
  }
}
