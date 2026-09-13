enum ExportFormat { imagePdf, searchablePdf, markdown, docx }

enum ExportJobStatus { queued, running, paused, completed, failed, cancelled }

enum PdfPageSize { a4, letter, legal, matchSource }

enum PdfOrientation { portrait, landscape, auto }

class PdfExportOptions {
  const PdfExportOptions({
    this.pageSize = PdfPageSize.matchSource,
    this.orientation = PdfOrientation.auto,
    this.marginPoints = 0,
    this.imageQuality = 0.85,
    this.searchable = true,
    this.password,
    this.ownerPassword,
    this.watermarkText,
  });

  final PdfPageSize pageSize;
  final PdfOrientation orientation;
  final double marginPoints;

  /// 0.0-1.0 JPEG quality used for page image compression.
  final double imageQuality;
  final bool searchable;
  final String? password;
  final String? ownerPassword;
  final String? watermarkText;
}

class MarkdownExportOptions {
  const MarkdownExportOptions({
    this.includePageBoundaryComments = true,
    this.includeFrontMatter = true,
    this.packageAsZip = false,
  });

  final bool includePageBoundaryComments;
  final bool includeFrontMatter;
  final bool packageAsZip;
}

enum DocxPageMode { reflowable, preservePageBreaks, facsimile }

class DocxExportOptions {
  const DocxExportOptions({this.pageMode = DocxPageMode.reflowable});

  final DocxPageMode pageMode;
}

/// A background export job (SPEC 10). Jobs are cancellable and resumable and
/// never mutate source page images.
class ExportJob {
  const ExportJob({
    required this.id,
    required this.projectId,
    required this.format,
    required this.status,
    required this.createdAt,
    this.progress = 0,
    this.error,
    this.outputPath,
    this.completedAt,
    this.pdfOptions,
    this.markdownOptions,
    this.docxOptions,
  });

  final String id;
  final String projectId;
  final ExportFormat format;
  final ExportJobStatus status;

  /// 0.0-1.0.
  final double progress;
  final String? error;
  final String? outputPath;
  final DateTime createdAt;
  final DateTime? completedAt;

  final PdfExportOptions? pdfOptions;
  final MarkdownExportOptions? markdownOptions;
  final DocxExportOptions? docxOptions;

  ExportJob copyWith({
    ExportJobStatus? status,
    double? progress,
    String? error,
    bool? clearError,
    String? outputPath,
    DateTime? completedAt,
  }) => ExportJob(
    id: id,
    projectId: projectId,
    format: format,
    status: status ?? this.status,
    createdAt: createdAt,
    progress: progress ?? this.progress,
    error: (clearError ?? false) ? null : (error ?? this.error),
    outputPath: outputPath ?? this.outputPath,
    completedAt: completedAt ?? this.completedAt,
    pdfOptions: pdfOptions,
    markdownOptions: markdownOptions,
    docxOptions: docxOptions,
  );
}
