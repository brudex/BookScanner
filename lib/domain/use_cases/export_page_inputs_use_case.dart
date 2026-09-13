import 'package:uuid/uuid.dart';

import '../models/export_job.dart';
import '../providers/document_export_provider.dart';
import '../repositories/export_job_repository.dart';
import '../repositories/page_path_allocator.dart';

/// Exports an already-assembled [ExportPageInput] list — as opposed to
/// [ExportProjectUseCase], which loads a single project's own pages from
/// [PageRepository] first. This is how the multi-source page-composition
/// flow (SPEC 6.5 "editing": merge/insert/replace/extract/split across
/// projects and imported PDFs/images) turns its working list into real PDF
/// output, reusing the same [DocumentExportProvider]/[ExportJobRepository]
/// job-lifecycle plumbing without touching `ExportProjectUseCase` itself.
///
/// Every [ExportJob] is still anchored to a real [hostProjectId] — the
/// `export_jobs` table enforces `project_id NOT NULL REFERENCES
/// projects(id)` — even when the exported pages were merged in from
/// elsewhere; the host project is just the FK anchor, not a claim that it
/// owns every page.
class ExportPageInputsUseCase {
  ExportPageInputsUseCase({
    required ExportJobRepository exportJobRepository,
    required DocumentExportProvider exportProvider,
    required PagePathAllocator paths,
    Uuid? uuid,
  }) : _exportJobRepository = exportJobRepository,
       _exportProvider = exportProvider,
       _paths = paths,
       _uuid = uuid ?? const Uuid();

  final ExportJobRepository _exportJobRepository;
  final DocumentExportProvider _exportProvider;
  final PagePathAllocator _paths;
  final Uuid _uuid;

  Future<ExportJob> exportPdf({
    required String hostProjectId,
    required String title,
    required List<ExportPageInput> pages,
    PdfExportOptions options = const PdfExportOptions(),
    String? author,
    String language = 'en',
    ExportProgressCallback? onProgress,
  }) async {
    var job = ExportJob(
      id: _uuid.v4(),
      projectId: hostProjectId,
      format: options.searchable
          ? ExportFormat.searchablePdf
          : ExportFormat.imagePdf,
      status: ExportJobStatus.running,
      createdAt: DateTime.now(),
      pdfOptions: options,
    );
    await _exportJobRepository.createJob(job);

    try {
      final input = ExportDocumentInput(
        projectId: hostProjectId,
        title: title,
        pages: pages,
        outputPathHint: _paths.exportPathFor(job.id, 'pdf'),
        author: author,
        language: language,
      );
      final output = await _exportProvider.exportPdf(
        input,
        options,
        onProgress: (p) {
          onProgress?.call(p);
          _updateProgress(job, p);
        },
      );
      job = job.copyWith(
        status: ExportJobStatus.completed,
        progress: 1,
        outputPath: output.outputPath,
        completedAt: DateTime.now(),
      );
      await _exportJobRepository.updateJob(job);
      return job;
    } on Exception catch (e) {
      // Same "return, don't rethrow" contract as ExportProjectUseCase.export
      // — a failed export is an expected business outcome the UI must
      // render, not exceptional control flow.
      job = job.copyWith(status: ExportJobStatus.failed, error: e.toString());
      await _exportJobRepository.updateJob(job);
      return job;
    }
  }

  /// One [ExportJob] + one output PDF per entry in [groups], in order. This
  /// is how both "split" (multiple groups) and "extract" (a single group —
  /// just call [exportPdf] directly with the selected subset) are expressed.
  Future<List<ExportJob>> splitPdf({
    required String hostProjectId,
    required String titlePrefix,
    required List<List<ExportPageInput>> groups,
    PdfExportOptions options = const PdfExportOptions(),
    String? author,
    String language = 'en',
    void Function(int completed, int total)? onJobProgress,
  }) async {
    final jobs = <ExportJob>[];
    for (var i = 0; i < groups.length; i++) {
      jobs.add(
        await exportPdf(
          hostProjectId: hostProjectId,
          title: '$titlePrefix ${i + 1}',
          pages: groups[i],
          options: options,
          author: author,
          language: language,
        ),
      );
      onJobProgress?.call(i + 1, groups.length);
    }
    return jobs;
  }

  Future<void> _updateProgress(ExportJob job, double progress) =>
      _exportJobRepository.updateJob(job.copyWith(progress: progress));
}
