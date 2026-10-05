import 'dart:async';

import '../models/scan_page.dart';
import '../repositories/page_repository.dart';
import 'capture_page_use_case.dart';

/// Removes shadows from freshly scanned book pages in the background.
///
/// The system scanner's Base mode keeps a page's natural contrast but not
/// even lighting; a hand or a book's curve often casts a shadow. Pages are
/// re-rendered one at a time with the Original look, which flattens the
/// lighting (see `removeShadowsAndStains`) without bleaching the paper.
///
/// Nothing here blocks or throws: Review opens at once and each thumbnail
/// updates when its page is done. A page the user already edited, or
/// deleted, is skipped, and a failure leaves the page as scanned.
class CleanScannedPagesUseCase {
  CleanScannedPagesUseCase({
    required PageRepository pageRepository,
    required CapturePageUseCase capturePageUseCase,
  }) : _pageRepository = pageRepository,
       _capturePageUseCase = capturePageUseCase;

  final PageRepository _pageRepository;
  final CapturePageUseCase _capturePageUseCase;

  final List<String> _queue = [];
  bool _running = false;
  Completer<void>? _idle;

  /// Queues [pageIds] for shadow removal and returns immediately.
  void enqueue(Iterable<String> pageIds) {
    _queue.addAll(pageIds);
    if (!_running) unawaited(_drain());
  }

  /// Completes when the queue is empty (for tests).
  Future<void> get idle => _idle?.future ?? Future<void>.value();

  Future<void> _drain() async {
    _running = true;
    _idle = Completer<void>();
    try {
      while (_queue.isNotEmpty) {
        final pageId = _queue.removeAt(0);
        try {
          final page = await _pageRepository.getPage(pageId);
          if (page == null || !_isUntouchedScan(page)) continue;
          await _capturePageUseCase.reprocessPage(
            page,
            filter: PageFilter.original,
          );
        } on Object {
          // Keep the page as scanned; never surface cleanup failures.
        }
      }
    } finally {
      _running = false;
      _idle?.complete();
    }
  }

  /// Still exactly what the scanner returned: no look, crop or adjustment
  /// applied yet, so re-rendering it cannot undo the user's own edits.
  static bool _isUntouchedScan(ScanPage page) =>
      page.filter == PageFilter.original &&
      page.processedImagePath == page.originalImagePath &&
      page.brightness == 0 &&
      page.contrast == 0 &&
      page.sharpness == 0 &&
      page.fineRotationDegrees == 0;
}
