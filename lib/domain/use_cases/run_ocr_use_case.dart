import '../models/ocr_block.dart';
import '../models/scan_page.dart';
import '../providers/ocr_provider.dart';
import '../repositories/ocr_repository.dart';
import '../repositories/page_repository.dart';
import '../repositories/settings_repository.dart';
import 'analyze_ocr_layout_use_case.dart';

/// Orchestrates the OCR pipeline stage for one page: recognize (native
/// provider) -> reconstruct layout (cross-platform heuristics) -> persist
/// (SPEC 9.4, 9.5: "Each pipeline stage stores its version and output").
class RunOcrUseCase {
  RunOcrUseCase({
    required PageRepository pageRepository,
    required OcrRepository ocrRepository,
    required OcrProvider ocrProvider,
    required SettingsRepository settingsRepository,
    AnalyzeOcrLayoutUseCase? layoutAnalysis,
  }) : _pageRepository = pageRepository,
       _ocrRepository = ocrRepository,
       _ocrProvider = ocrProvider,
       _settingsRepository = settingsRepository,
       _layoutAnalysis = layoutAnalysis ?? AnalyzeOcrLayoutUseCase();

  final PageRepository _pageRepository;
  final OcrRepository _ocrRepository;
  final OcrProvider _ocrProvider;
  final SettingsRepository _settingsRepository;
  final AnalyzeOcrLayoutUseCase _layoutAnalysis;

  /// Returns existing blocks if OCR already ran for this page, unless
  /// [force] is set (e.g. after a crop change invalidates the OCR stage).
  Future<List<OcrBlock>> call(String pageId, {bool force = false}) async {
    if (!force && await _ocrRepository.hasOcr(pageId)) {
      return _ocrRepository.getBlocks(pageId);
    }
    final page = await _pageRepository.getPage(pageId);
    if (page == null) {
      throw StateError('Page not found: $pageId');
    }

    final settings = await _settingsRepository.getSettings();
    final imagePath = page.processedImagePath ?? page.originalImagePath;
    final result = await _ocrProvider.recognize(
      OcrRequest(imagePath: imagePath, languages: settings.ocrLanguages),
    );

    final analyzed = _layoutAnalysis(pageId, result.blocks);
    await _ocrRepository.saveBlocks(pageId, analyzed);

    await _pageRepository.updatePage(
      page.copyWith(
        stages: {
          ...page.stages,
          PipelineStage.ocr: StageRecord(
            version: 1,
            providerInfo: result.providerInfo,
            completedAtMs: DateTime.now().millisecondsSinceEpoch,
          ),
        },
      ),
    );

    return analyzed;
  }
}
