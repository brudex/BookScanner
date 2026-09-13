import '../providers/document_export_provider.dart';
import '../repositories/ocr_repository.dart';
import '../repositories/page_repository.dart';

/// Builds the provider-neutral [ExportPageInput] list for a project's
/// current pages, in project order. Shared by [ExportProjectUseCase] (single
/// project export) and the multi-source page-composition flow (task 11),
/// which both need the same "one project's pages -> ExportPageInput list"
/// projection.
class LoadProjectPageInputsUseCase {
  LoadProjectPageInputsUseCase({
    required PageRepository pageRepository,
    required OcrRepository ocrRepository,
  }) : _pageRepository = pageRepository,
       _ocrRepository = ocrRepository;

  final PageRepository _pageRepository;
  final OcrRepository _ocrRepository;

  Future<List<ExportPageInput>> call(String projectId) async {
    final pages = await _pageRepository.getPages(projectId);
    final pageInputs = <ExportPageInput>[];
    for (final page in pages) {
      final blocks = await _ocrRepository.getBlocks(page.id);
      pageInputs.add(
        ExportPageInput(
          pageId: page.id,
          imagePath: page.processedImagePath ?? page.originalImagePath,
          rotationDegrees: page.rotationDegrees,
          logicalPageLabel: page.logicalPageLabel,
          ocrBlocks: blocks,
        ),
      );
    }
    return pageInputs;
  }
}
