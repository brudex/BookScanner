import '../models/provider_info.dart';

/// One rasterized page from an existing PDF document.
///
/// This is a bitmap, not a re-imported vector/text page: no PDF-parsing
/// library is available anywhere in this stack (SPEC 9.7 — see
/// [PdfRasterizerProvider] doc comment), so callers must not populate
/// [ExportPageInput.ocrBlocks] from a rasterized page's own content and must
/// not claim the resulting export page is searchable unless OCR is
/// explicitly rerun on it.
class RasterizedPdfPage {
  const RasterizedPdfPage({
    required this.pageIndex,
    required this.pngBytes,
    required this.widthPx,
    required this.heightPx,
  });

  /// 0-based index within the source PDF.
  final int pageIndex;
  final List<int> pngBytes;
  final int widthPx;
  final int heightPx;
}

/// Reads an existing PDF's pages as bitmaps (SPEC 6.5 "editing": merging in
/// or splitting out pages from a PDF the user already has). Deliberately
/// bitmap-only: neither `package:pdf` (write-only, no shipped concrete
/// `PdfDocumentParserBase` implementation) nor `package:printing` exposes a
/// way to read an existing PDF's vector/text object graph, only to
/// rasterize its pages via the native PDFium/PDFKit renderer. Flattening
/// imported PDF pages to images is a known, documented tradeoff, not a bug.
abstract interface class PdfRasterizerProvider {
  ProviderInfo get info;

  /// Rasterizes [pageIndices] (0-based, into the source PDF), or every page
  /// if null, from the PDF at [pdfPath] at [dpi]. There is no page-count-only
  /// API in the underlying renderer, so enumerating a PDF's pages always
  /// means rasterizing all of them at least once (do this cheaply, at a low
  /// [dpi], for any "pick pages to import" UI).
  ///
  /// [dpi] defaults to 150 because
  /// `DartDocumentExportProvider._pdfPageFormat`'s `matchSource` branch
  /// assumes source pixel dimensions were produced at 150 DPI when computing
  /// the output PDF page's physical size — rasterizing at a different DPI
  /// without also changing that formula would size imported pages wrong.
  Stream<RasterizedPdfPage> rasterize(
    String pdfPath, {
    List<int>? pageIndices,
    double dpi = 150,
  });
}
