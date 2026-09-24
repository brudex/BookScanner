import '../models/export_job.dart';
import '../providers/document_export_provider.dart';
import '../repositories/ocr_repository.dart';
import '../repositories/page_path_allocator.dart';
import '../repositories/page_repository.dart';
import 'load_project_page_inputs_use_case.dart';

/// Exports a project's pages as standalone JPG/PNG files, zipped together
/// (SPEC 6.5 "Convert... PDF pages to JPG/PNG"). Deliberately outside the
/// [ExportJob]-tracked pipeline used by PDF/Markdown/DOCX -- an image dump
/// has no format-specific options worth persisting across an app restart,
/// so it runs as a single direct call rather than adding a fifth
/// [ExportFormat] and a matching job-options migration for no real benefit.
class ExportImagesUseCase {
  ExportImagesUseCase({
    required PageRepository pageRepository,
    required OcrRepository ocrRepository,
    required DocumentExportProvider exportProvider,
    required PagePathAllocator paths,
    LoadProjectPageInputsUseCase? pageInputLoader,
  }) : _exportProvider = exportProvider,
       _paths = paths,
       _pageInputLoader =
           pageInputLoader ??
           LoadProjectPageInputsUseCase(
             pageRepository: pageRepository,
             ocrRepository: ocrRepository,
           );

  final DocumentExportProvider _exportProvider;
  final PagePathAllocator _paths;
  final LoadProjectPageInputsUseCase _pageInputLoader;

  Future<ExportOutput> call({
    required String projectId,
    required String title,
    ImageExportOptions options = const ImageExportOptions(),
  }) async {
    final pages = await _pageInputLoader(projectId);
    final input = ExportDocumentInput(
      projectId: projectId,
      title: title,
      pages: pages,
      outputPathHint: _paths.exportPathFor(
        '$projectId-images-${DateTime.now().millisecondsSinceEpoch}',
        'images',
      ),
    );
    return _exportProvider.exportImages(input, options);
  }
}
