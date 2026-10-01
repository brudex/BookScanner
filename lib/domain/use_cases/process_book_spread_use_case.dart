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

/// Fast book capture. A shutter tap stores the full photo — no edge crop,
/// document filter, curve flatten, or OCR. Two-page mode only splits the
/// frame down the middle so the next page can be shot immediately. Crop,
/// filters, and OCR stay manual after the session.
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

  /// Still injected so the scanner graph stays stable. Fast book capture
  /// does not run page detection.
  // ignore: unused_field
  final PageDetectionProvider _detectionProvider;
  final PagePathAllocator _paths;
  final Uuid _uuid;

  // Fast capture does not enhance. Crop and filters run in the post-capture
  // page walk, not from Review.
  // ignore: unused_field
  final ImageEnhancementProvider _enhancementProvider;

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

    // Center split only. Gutter hunting treats a text column as the spine
    // and saves a skinny strip instead of the page.
    final split = await _dewarpProvider.splitSpread(
      spreadOriginalPath,
      gutterXOverride: 0.5,
    );

    final leftPage = await _buildPage(
      pageId: leftId,
      siblingId: rightId,
      rawImagePath: split.leftPageImagePath,
      projectId: projectId,
      capturedAtMs: capture.capturedAtMs,
    );
    final rightPage = await _buildPage(
      pageId: rightId,
      siblingId: leftId,
      rawImagePath: split.rightPageImagePath,
      projectId: projectId,
      capturedAtMs: capture.capturedAtMs,
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

  /// Single-page book capture: the whole photo, unchanged. No split.
  Future<List<ScanPage>> processSinglePage({
    required StillCapture capture,
    required String projectId,
    required int sequence,
  }) async {
    final pageId = _uuid.v4();
    final page = await _buildPage(
      pageId: pageId,
      siblingId: null,
      rawImagePath: capture.originalImagePath,
      projectId: projectId,
      capturedAtMs: capture.capturedAtMs,
    );
    final withSeq = page.copyWith(sequence: sequence);
    await _pageRepository.addPage(withSeq);
    return [withSeq];
  }

  /// Re-splits the saved full photo at [gutterX] and stores both halves
  /// as-is. Does not crop, filter, or dewarp.
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
    );
    final newRight = await _buildPage(
      pageId: rightPage.id,
      siblingId: leftPage.id,
      rawImagePath: split.rightPageImagePath,
      projectId: rightPage.projectId,
      capturedAtMs: rightPage.capturedAtMs,
    );

    final updatedLeft = newLeft.copyWith(sequence: leftPage.sequence);
    final updatedRight = newRight.copyWith(sequence: rightPage.sequence);
    await _pageRepository.updatePage(updatedLeft);
    await _pageRepository.updatePage(updatedRight);
    return [updatedLeft, updatedRight];
  }

  Future<ScanPage> _buildPage({
    required String pageId,
    required String? siblingId,
    required String rawImagePath,
    required String projectId,
    required int? capturedAtMs,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final originalPath = _paths.originalPathFor(pageId, ext: 'jpg');
    if (rawImagePath != originalPath) {
      await File(rawImagePath).copy(originalPath);
    }

    return ScanPage(
      id: pageId,
      projectId: projectId,
      sequence: 0,
      originalImagePath: originalPath,
      processedImagePath: originalPath,
      thumbnailPath: originalPath,
      cropPoints: Quad.fullFrame,
      filter: PageFilter.original,
      qualityScore: 0.9,
      warnings: const {},
      spreadSiblingPageId: siblingId,
      status: PageStatus.ready,
      capturedAtMs: capturedAtMs,
      stages: {
        if (siblingId != null)
          PipelineStage.split: StageRecord(
            version: 1,
            providerInfo: _dewarpProvider.info,
            completedAtMs: now,
          ),
      },
    );
  }
}
