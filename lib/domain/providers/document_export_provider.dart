import '../models/export_job.dart';
import '../models/ocr_block.dart';
import '../models/provider_info.dart';

/// Immutable, file-path-based description of one page to export. Carries no
/// native object handles or in-memory pixel buffers across the boundary
/// (SPEC 9.7).
class ExportPageInput {
  const ExportPageInput({
    required this.pageId,
    required this.imagePath,
    required this.rotationDegrees,
    this.logicalPageLabel,
    this.ocrBlocks = const [],
  });

  final String pageId;
  final String imagePath;
  final int rotationDegrees;
  final String? logicalPageLabel;
  final List<OcrBlock> ocrBlocks;

  ExportPageInput copyWith({
    String? pageId,
    String? imagePath,
    int? rotationDegrees,
    String? logicalPageLabel,
    bool clearLogicalPageLabel = false,
    List<OcrBlock>? ocrBlocks,
  }) => ExportPageInput(
    pageId: pageId ?? this.pageId,
    imagePath: imagePath ?? this.imagePath,
    rotationDegrees: rotationDegrees ?? this.rotationDegrees,
    logicalPageLabel: clearLogicalPageLabel
        ? null
        : (logicalPageLabel ?? this.logicalPageLabel),
    ocrBlocks: ocrBlocks ?? this.ocrBlocks,
  );
}

class ExportDocumentInput {
  const ExportDocumentInput({
    required this.projectId,
    required this.title,
    required this.pages,
    required this.outputPathHint,
    this.author,
    this.language = 'en',
    this.isbn,
    this.sourceMetadataNote,
  });

  final String projectId;
  final String title;
  final List<ExportPageInput> pages;

  /// File path (without extension assumptions beyond what the caller
  /// chose) the adapter must write its primary output to. Callers own path
  /// allocation (via [AppPaths]) so providers stay decoupled from storage
  /// layout.
  final String outputPathHint;
  final String? author;
  final String language;
  final String? isbn;
  final String? sourceMetadataNote;
}

class ExportOutput {
  const ExportOutput({
    required this.outputPath,
    required this.providerInfo,
    this.assetPaths = const [],
  });

  final String outputPath;
  final List<String> assetPaths;
  final ProviderInfo providerInfo;
}

typedef ExportProgressCallback = void Function(double progress);

/// Generates PDF, Markdown, and DOCX artifacts from already-processed pages
/// (SPEC 6.5, 6.6, 6.7). The default adapter runs entirely on-device; a
/// remote conversion-worker adapter may be substituted for complex DOCX
/// reconstruction behind the same contract (SPEC 9.8), with explicit user
/// consent enforced by the caller before any upload.
abstract interface class DocumentExportProvider {
  ProviderInfo get info;

  bool supportsFormat(ExportFormat format);

  Future<ExportOutput> exportPdf(
    ExportDocumentInput input,
    PdfExportOptions options, {
    ExportProgressCallback? onProgress,
  });

  /// Dry-run estimate (no file written) of the PDF's output size in bytes
  /// under [options] -- used by a compress-quality preview (SPEC 6.5).
  Future<int> estimatePdfSizeBytes(
    ExportDocumentInput input,
    PdfExportOptions options,
  );

  /// Exports each page as a standalone JPG/PNG file, zipped together (SPEC
  /// 6.5 "Convert... PDF pages to JPG/PNG").
  Future<ExportOutput> exportImages(
    ExportDocumentInput input,
    ImageExportOptions options, {
    ExportProgressCallback? onProgress,
  });

  Future<ExportOutput> exportMarkdown(
    ExportDocumentInput input,
    MarkdownExportOptions options, {
    ExportProgressCallback? onProgress,
  });

  Future<ExportOutput> exportDocx(
    ExportDocumentInput input,
    DocxExportOptions options, {
    ExportProgressCallback? onProgress,
  });

  /// Writes an EPUB 3 package (XHTML chapters, optional page images).
  Future<ExportOutput> exportEpub(
    ExportDocumentInput input,
    EpubExportOptions options, {
    ExportProgressCallback? onProgress,
  });
}
