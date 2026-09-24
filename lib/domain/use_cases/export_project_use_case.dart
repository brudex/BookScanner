import 'package:uuid/uuid.dart';

import '../models/export_job.dart';
import '../providers/document_export_provider.dart';
import '../repositories/export_job_repository.dart';
import '../repositories/ocr_repository.dart';
import '../repositories/page_path_allocator.dart';
import '../repositories/page_repository.dart';
import 'load_project_page_inputs_use_case.dart';

/// Orchestrates a full project export: gathers ordered pages and their OCR
/// blocks (if any), builds the provider-neutral [ExportDocumentInput], and
/// drives the selected [DocumentExportProvider] format method while keeping
/// [ExportJob] progress persisted so the UI can show progress and the job
/// can be inspected after the app restarts (SPEC 11: "Long operations
/// expose progress, can be cancelled safely").
class ExportProjectUseCase {
  ExportProjectUseCase({
    required PageRepository pageRepository,
    required OcrRepository ocrRepository,
    required ExportJobRepository exportJobRepository,
    required DocumentExportProvider exportProvider,
    required PagePathAllocator paths,
    LoadProjectPageInputsUseCase? pageInputLoader,
    Uuid? uuid,
  }) : _exportJobRepository = exportJobRepository,
       _exportProvider = exportProvider,
       _paths = paths,
       _pageInputLoader =
           pageInputLoader ??
           LoadProjectPageInputsUseCase(
             pageRepository: pageRepository,
             ocrRepository: ocrRepository,
           ),
       _uuid = uuid ?? const Uuid();

  final ExportJobRepository _exportJobRepository;
  final DocumentExportProvider _exportProvider;
  final PagePathAllocator _paths;
  final LoadProjectPageInputsUseCase _pageInputLoader;
  final Uuid _uuid;

  Future<ExportJob> export({
    required String projectId,
    required String title,
    required ExportFormat format,
    String? author,
    String language = 'en',
    String? isbn,
    PdfExportOptions? pdfOptions,
    MarkdownExportOptions? markdownOptions,
    DocxExportOptions? docxOptions,
  }) async {
    var job = ExportJob(
      id: _uuid.v4(),
      projectId: projectId,
      format: format,
      status: ExportJobStatus.running,
      createdAt: DateTime.now(),
      pdfOptions: pdfOptions,
      markdownOptions: markdownOptions,
      docxOptions: docxOptions,
    );
    await _exportJobRepository.createJob(job);

    try {
      final pageInputs = await _pageInputLoader(projectId);

      final extension = switch (format) {
        ExportFormat.imagePdf || ExportFormat.searchablePdf => 'pdf',
        ExportFormat.markdown => 'md',
        ExportFormat.docx => 'docx',
      };
      final outputPath = _paths.exportPathFor(job.id, extension);

      final input = ExportDocumentInput(
        projectId: projectId,
        title: title,
        pages: pageInputs,
        outputPathHint: outputPath,
        author: author,
        language: language,
        isbn: isbn,
      );

      final ExportOutput output;
      switch (format) {
        case ExportFormat.imagePdf:
          output = await _exportProvider.exportPdf(
            input,
            (pdfOptions ?? const PdfExportOptions()).copyWithSearchable(false),
            onProgress: (p) => _updateProgress(job, p),
          );
        case ExportFormat.searchablePdf:
          output = await _exportProvider.exportPdf(
            input,
            (pdfOptions ?? const PdfExportOptions()).copyWithSearchable(true),
            onProgress: (p) => _updateProgress(job, p),
          );
        case ExportFormat.markdown:
          output = await _exportProvider.exportMarkdown(
            input,
            markdownOptions ?? const MarkdownExportOptions(),
            onProgress: (p) => _updateProgress(job, p),
          );
        case ExportFormat.docx:
          output = await _exportProvider.exportDocx(
            input,
            docxOptions ?? const DocxExportOptions(),
            onProgress: (p) => _updateProgress(job, p),
          );
      }

      job = job.copyWith(
        status: ExportJobStatus.completed,
        progress: 1,
        outputPath: output.outputPath,
        completedAt: DateTime.now(),
      );
      await _exportJobRepository.updateJob(job);
      return job;
    } on Exception catch (e) {
      // Returned, not rethrown: a failed export is an expected business
      // outcome the UI must render (`ExportScreen`'s `_FailedView`,
      // including retry), not exceptional control flow. Rethrowing here
      // previously meant the caller's `job` local variable was never
      // assigned when an export failed, so `ExportViewModel.job` stayed
      // null and the failed/retry UI was unreachable -- found via a widget
      // test that (correctly) couldn't find "Export failed" on screen.
      job = job.copyWith(status: ExportJobStatus.failed, error: e.toString());
      await _exportJobRepository.updateJob(job);
      return job;
    }
  }

  Future<void> _updateProgress(ExportJob job, double progress) =>
      _exportJobRepository.updateJob(job.copyWith(progress: progress));

  /// Dry-run size estimate for a compress-quality preview (SPEC 6.5),
  /// reusing the same page-input loading `export` does without writing a
  /// job or a file.
  Future<int> estimatePdfSizeBytes({
    required String projectId,
    PdfExportOptions options = const PdfExportOptions(),
  }) async {
    final pageInputs = await _pageInputLoader(projectId);
    final input = ExportDocumentInput(
      projectId: projectId,
      title: '',
      pages: pageInputs,
      outputPathHint: '',
    );
    return _exportProvider.estimatePdfSizeBytes(input, options);
  }
}

extension on PdfExportOptions {
  PdfExportOptions copyWithSearchable(bool searchable) => PdfExportOptions(
    pageSize: pageSize,
    orientation: orientation,
    marginPoints: marginPoints,
    imageQuality: imageQuality,
    maxDimensionPx: maxDimensionPx,
    searchable: searchable,
    password: password,
    ownerPassword: ownerPassword,
    watermarkText: watermarkText,
  );
}
