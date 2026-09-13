import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../domain/models/export_job.dart';
import '../../../domain/models/provider_info.dart';
import '../../../domain/providers/document_export_provider.dart';
import 'docx_writer.dart';
import 'markdown_writer.dart';

/// Default on-device export adapter (SPEC 6.5, 6.6, 6.7). Pure Dart — no
/// vendor SDK — so it runs identically on Android and iOS and can be
/// replaced by a remote conversion-worker adapter behind the same
/// [DocumentExportProvider] contract for complex DOCX reconstruction
/// (SPEC 9.8) without any Flutter-side change.
class DartDocumentExportProvider implements DocumentExportProvider {
  @override
  ProviderInfo get info => const ProviderInfo(
    providerName: 'dart-export-local',
    adapterVersion: '1.0.0',
  );

  @override
  bool supportsFormat(ExportFormat format) => true;

  @override
  Future<ExportOutput> exportPdf(
    ExportDocumentInput input,
    PdfExportOptions options, {
    ExportProgressCallback? onProgress,
  }) async {
    final doc = pw.Document(
      title: input.title,
      author: input.author,
      creator: 'BookScanner',
      subject: input.title,
    );

    for (var i = 0; i < input.pages.length; i++) {
      final page = input.pages[i];
      final bytes = await File(page.imagePath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) continue;
      var oriented = img.bakeOrientation(decoded);
      if (page.rotationDegrees != 0) {
        oriented = img.copyRotate(oriented, angle: page.rotationDegrees);
      }
      final jpg = img.encodeJpg(
        oriented,
        quality: (options.imageQuality * 100).round().clamp(10, 100),
      );
      final memImage = pw.MemoryImage(jpg);

      final pageFormat = _pdfPageFormat(
        options,
        oriented.width,
        oriented.height,
      );

      doc.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: pw.EdgeInsets.all(options.marginPoints),
          build: (context) => pw.Stack(
            children: [
              pw.Positioned.fill(
                child: pw.Image(memImage, fit: pw.BoxFit.fill),
              ),
              if (options.searchable)
                ..._invisibleTextOverlay(
                  page,
                  oriented.width,
                  oriented.height,
                  pageFormat,
                ),
              if (options.watermarkText != null)
                _watermark(options.watermarkText!, pageFormat),
            ],
          ),
        ),
      );
      onProgress?.call((i + 1) / input.pages.length);
    }

    if (options.password != null || options.ownerPassword != null) {
      // Standard Security Handler (password encryption) is tracked as a
      // follow-up in IMPLEMENTATION_STATUS.md (SPEC 6.5) and intentionally
      // not faked here: silently exporting an unprotected PDF when the user
      // requested a password would violate their stated privacy intent.
      throw const ProviderException(
        ProviderErrorCategory.unsupportedDevice,
        'PDF password protection is not yet implemented',
        providerName: 'dart-export-local',
      );
    }
    final bytes = await doc.save();
    await File(input.outputPathHint).writeAsBytes(bytes);

    return ExportOutput(outputPath: input.outputPathHint, providerInfo: info);
  }

  PdfPageFormat _pdfPageFormat(
    PdfExportOptions options,
    int pxWidth,
    int pxHeight,
  ) {
    PdfPageFormat base = switch (options.pageSize) {
      PdfPageSize.a4 => PdfPageFormat.a4,
      PdfPageSize.letter => PdfPageFormat.letter,
      PdfPageSize.legal => PdfPageFormat.legal,
      PdfPageSize.matchSource => PdfPageFormat(
        pxWidth * 72 / 150,
        pxHeight * 72 / 150,
      ),
    };
    final isLandscapeSource = pxWidth > pxHeight;
    final wantLandscape = switch (options.orientation) {
      PdfOrientation.portrait => false,
      PdfOrientation.landscape => true,
      PdfOrientation.auto => isLandscapeSource,
    };
    if (wantLandscape && base.width < base.height) {
      base = base.landscape;
    } else if (!wantLandscape && base.width > base.height) {
      base = base.portrait;
    }
    return base;
  }

  List<pw.Widget> _invisibleTextOverlay(
    ExportPageInput page,
    int pxWidth,
    int pxHeight,
    PdfPageFormat format,
  ) {
    final widgets = <pw.Widget>[];
    for (final block in page.ocrBlocks) {
      if (block.text.trim().isEmpty) continue;
      final poly = block.boundingPolygon.points;
      if (poly.isEmpty) continue;
      final minX = poly.map((p) => p.x).reduce((a, b) => a < b ? a : b);
      final maxX = poly.map((p) => p.x).reduce((a, b) => a > b ? a : b);
      final minY = poly.map((p) => p.y).reduce((a, b) => a < b ? a : b);
      final maxY = poly.map((p) => p.y).reduce((a, b) => a > b ? a : b);
      final left = minX * format.width;
      final top = minY * format.height;
      final width = (maxX - minX) * format.width;
      final height = (maxY - minY) * format.height;
      if (width <= 0 || height <= 0) continue;
      widgets.add(
        pw.Positioned(
          left: left,
          top: top,
          child: pw.SizedBox(
            width: width,
            height: height,
            child: pw.Text(
              block.text,
              style: pw.TextStyle(
                fontSize: height.clamp(4, 400),
                color: const PdfColor(0, 0, 0, 0),
              ),
              maxLines: 1,
              overflow: pw.TextOverflow.clip,
            ),
          ),
        ),
      );
    }
    return widgets;
  }

  pw.Widget _watermark(String text, PdfPageFormat format) => pw.Positioned.fill(
    child: pw.Center(
      child: pw.Transform.rotate(
        angle: 0.6,
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: format.width / 8,
            color: PdfColors.grey300,
          ),
        ),
      ),
    ),
  );

  @override
  Future<ExportOutput> exportMarkdown(
    ExportDocumentInput input,
    MarkdownExportOptions options, {
    ExportProgressCallback? onProgress,
  }) =>
      MarkdownWriter(info: info).write(input, options, onProgress: onProgress);

  @override
  Future<ExportOutput> exportDocx(
    ExportDocumentInput input,
    DocxExportOptions options, {
    ExportProgressCallback? onProgress,
  }) => DocxWriter(info: info).write(input, options, onProgress: onProgress);
}
