import 'dart:io';
import 'dart:math' as math;

import 'package:printing/printing.dart';

import '../../../../domain/models/capture_models.dart';
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

  /// DPI of the cheap first pass that only measures each page's size.
  static const double _probeDpi = 4;

  @override
  Stream<RasterizedPdfPage> rasterize(
    String pdfPath, {
    List<int>? pageIndices,
    double dpi = 150,
  }) async* {
    final bytes = await File(pdfPath).readAsBytes();
    // PDFs can declare huge pages (a photo saved as PDF, or a 2261 x 3200 pt
    // canvas); at [dpi] one such page needed a 633 MB bitmap and the import
    // died. Measure each page first, then lower its DPI so the long side
    // stays within StoredPageLimits.maxLongSidePx.
    final sizesPt = <int, double>{};
    var probeIndex = 0;
    await for (final probe in Printing.raster(
      bytes,
      pages: pageIndices,
      dpi: _probeDpi,
    )) {
      final index = pageIndices != null ? pageIndices[probeIndex] : probeIndex;
      sizesPt[index] = math.max(probe.width, probe.height) * 72 / _probeDpi;
      probeIndex++;
    }
    for (final index in sizesPt.keys) {
      final longSidePt = sizesPt[index]!;
      final maxDpi = StoredPageLimits.maxLongSidePx * 72 / longSidePt;
      await for (final raster in Printing.raster(
        bytes,
        pages: [index],
        dpi: math.min(dpi, maxDpi),
      )) {
        yield RasterizedPdfPage(
          pageIndex: index,
          pngBytes: await raster.toPng(),
          widthPx: raster.width,
          heightPx: raster.height,
        );
      }
    }
  }
}
