import 'package:flutter/foundation.dart';

import '../../../../domain/models/ocr_block.dart';
import '../../../../domain/models/scan_page.dart';
import '../../../../domain/repositories/ocr_repository.dart';
import '../../../../domain/repositories/page_repository.dart';
import '../../../../domain/use_cases/run_ocr_use_case.dart';

/// Backs the OCR review/correction screen (SPEC 6.4: "Users can correct
/// recognized text, with low-confidence spans flagged for review").
class OcrReviewViewModel extends ChangeNotifier {
  OcrReviewViewModel({
    required this.pageId,
    required PageRepository pageRepository,
    required OcrRepository ocrRepository,
    required RunOcrUseCase runOcrUseCase,
  }) : _pageRepository = pageRepository,
       _ocrRepository = ocrRepository,
       _runOcrUseCase = runOcrUseCase;

  final String pageId;
  final PageRepository _pageRepository;
  final OcrRepository _ocrRepository;
  final RunOcrUseCase _runOcrUseCase;

  ScanPage? _page;
  ScanPage? get page => _page;

  List<OcrBlock> _blocks = const [];
  List<OcrBlock> get blocks => _blocks;

  // Deliberately not derived from `_blocks.isNotEmpty`: a page with no text
  // (e.g. a blank or image-only page) legitimately recognizes zero blocks,
  // which must not be shown as "OCR has not been run yet" forever. The
  // pipeline-stage record (written by RunOcrUseCase regardless of block
  // count) is the authoritative "did this run" signal.
  bool _hasRun = false;
  bool get hasRun => _hasRun;

  bool _loading = true;
  bool get loading => _loading;

  bool _running = false;
  bool get running => _running;

  Object? _error;
  Object? get error => _error;

  Future<void> initialize() async {
    try {
      final page = await _pageRepository.getPage(pageId);
      if (page == null) {
        _error = StateError('Page not found');
        return;
      }
      _page = page;
      _hasRun = page.stages.containsKey(PipelineStage.ocr);
      _blocks = await _ocrRepository.getBlocks(pageId);
    } on Exception catch (e) {
      _error = e;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> runOcr({bool force = false}) async {
    _running = true;
    _error = null;
    notifyListeners();
    try {
      _blocks = await _runOcrUseCase(pageId, force: force);
      _hasRun = true;
      _page = await _pageRepository.getPage(pageId) ?? _page;
    } on Exception catch (e) {
      _error = e;
    } finally {
      _running = false;
      notifyListeners();
    }
  }

  Future<void> correctBlock(String blockId, String newText) async {
    await _ocrRepository.correctBlock(pageId, blockId, newText);
    _blocks = await _ocrRepository.getBlocks(pageId);
    notifyListeners();
  }
}
