import 'dart:io';

import 'package:printing/printing.dart';

import '../../../../domain/models/provider_info.dart';
import '../../../../domain/providers/pdf_rasterizer_provider.dart';

/// Real, cross-platform adapter backed by `package:printing`'s native
/// PDFium (Android) / PDFKit (iOS) rasterizer. Unlike the capture/OCR
/// providers, no per-platform branching is needed here — `printing` already
/// covers both platforms behind one Dart API.
class PrintingPdfRasterizerProvider implements PdfRasterizerProvider {
  @override
  ProviderInfo get info => const ProviderInfo(
    providerName: 'printing-rasterizer',
    adapterVersion: '1.0.0',
  );

  @override
  Stream<RasterizedPdfPage> rasterize(
    String pdfPath, {
    List<int>? pageIndices,
    double dpi = 150,
  }) async* {
    final bytes = await File(pdfPath).readAsBytes();
    var i = 0;
    await for (final raster in Printing.raster(
      bytes,
      pages: pageIndices,
      dpi: dpi,
    )) {
      yield RasterizedPdfPage(
        pageIndex: pageIndices != null ? pageIndices[i] : i,
        pngBytes: await raster.toPng(),
        widthPx: raster.width,
        heightPx: raster.height,
      );
      i++;
    }
  }
}
