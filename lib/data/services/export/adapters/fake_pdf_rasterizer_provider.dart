import 'package:image/image.dart' as img;

import '../../../../domain/models/provider_info.dart';
import '../../../../domain/providers/pdf_rasterizer_provider.dart';

/// Deterministic in-memory rasterizer used by contract/unit/widget tests
/// (mirrors [FakeOcrProvider]/[FakeCaptureProvider]). Generates synthetic,
/// distinguishable-per-page PNGs with no platform channel involved, so it
/// runs under plain `flutter test` — unlike [PrintingPdfRasterizerProvider],
/// which needs a real device/simulator's native PDF renderer.
class FakePdfRasterizerProvider implements PdfRasterizerProvider {
  FakePdfRasterizerProvider({
    this.pageCountForPath = const {},
    this.defaultPageCount = 3,
  });

  /// Page count to report for a given source path; falls back to
  /// [defaultPageCount] for any path not listed.
  final Map<String, int> pageCountForPath;
  final int defaultPageCount;

  @override
  ProviderInfo get info => const ProviderInfo(
    providerName: 'fake-pdf-rasterizer',
    adapterVersion: '1.0.0-test',
  );

  @override
  Stream<RasterizedPdfPage> rasterize(
    String pdfPath, {
    List<int>? pageIndices,
    double dpi = 150,
  }) async* {
    final count = pageCountForPath[pdfPath] ?? defaultPageCount;
    final indices = pageIndices ?? List.generate(count, (i) => i);
    final widthPx = (dpi * 8.5).round();
    final heightPx = (dpi * 11).round();
    for (final i in indices) {
      final page = img.Image(width: widthPx, height: heightPx);
      final shade = 180 + (i * 15) % 60;
      img.fill(page, color: img.ColorRgb8(shade, shade, shade));
      yield RasterizedPdfPage(
        pageIndex: i,
        pngBytes: img.encodePng(page),
        widthPx: widthPx,
        heightPx: heightPx,
      );
    }
  }
}
