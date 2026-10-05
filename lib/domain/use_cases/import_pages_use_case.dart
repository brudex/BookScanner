import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/capture_models.dart';
import '../models/provider_info.dart';
import '../models/scan_page.dart';
import '../providers/pdf_rasterizer_provider.dart';
import '../repositories/page_path_allocator.dart';
import 'capture_page_use_case.dart';

/// Copies an image from [source] to [dest], bounding its resolution.
typedef ImageStorer = Future<void> Function(String source, String dest);

/// Adds gallery photos or PDF pages to a project, keeping each page's
/// original as-is (no crop or filter), in order after [startSequence].
///
/// Picked files are copied into app storage first: the image picker hands
/// back files in the app's cache, which Android may clear at any time, and
/// a page whose original disappears can no longer be cropped, filtered or
/// reverted. The copy also bounds the resolution like scanner pages
/// ([StoredPageLimits]).
class ImportPagesUseCase {
  ImportPagesUseCase({
    required CapturePageUseCase capturePageUseCase,
    required PagePathAllocator paths,
    required PdfRasterizerProvider rasterizer,
    required ImageStorer storeImage,
    Uuid? uuid,
  }) : _capturePageUseCase = capturePageUseCase,
       _paths = paths,
       _rasterizer = rasterizer,
       _storeImage = storeImage,
       _uuid = uuid ?? const Uuid();

  final CapturePageUseCase _capturePageUseCase;
  final PagePathAllocator _paths;
  final PdfRasterizerProvider _rasterizer;
  final ImageStorer _storeImage;
  final Uuid _uuid;

  /// Imports [imagePaths] as pages. Returns the pages added, in order.
  Future<List<ScanPage>> importImages(
    List<String> imagePaths, {
    required String projectId,
    required int startSequence,
    String providerName = 'gallery-import',
  }) async {
    final pages = <ScanPage>[];
    for (final source in imagePaths) {
      final dest = await storeImage(source);
      pages.add(
        await _save(
          dest,
          projectId: projectId,
          sequence: startSequence + pages.length,
          providerName: providerName,
        ),
      );
    }
    return pages;
  }

  /// Copies [source] into app storage (bounded resolution) and returns the
  /// stored path, for callers that save the page themselves.
  Future<String> storeImage(String source) async {
    final ext = p.extension(source).replaceFirst('.', '').toLowerCase();
    final dest = _paths.originalPathFor(
      _uuid.v4(),
      ext: ext.isEmpty ? 'jpg' : ext,
    );
    await File(dest).parent.create(recursive: true);
    await _storeImage(source, dest);
    return dest;
  }

  /// Imports every page of the PDF at [pdfPath] as an image page. Returns
  /// the pages added, in order.
  Future<List<ScanPage>> importPdf(
    String pdfPath, {
    required String projectId,
    required int startSequence,
  }) async {
    final pages = <ScanPage>[];
    await for (final raster in _rasterizer.rasterize(pdfPath)) {
      final dest = _paths.originalPathFor(_uuid.v4(), ext: 'png');
      await File(dest).parent.create(recursive: true);
      await File(dest).writeAsBytes(raster.pngBytes);
      pages.add(
        await _save(
          dest,
          projectId: projectId,
          sequence: startSequence + pages.length,
          providerName: 'pdf-import',
        ),
      );
    }
    return pages;
  }

  Future<ScanPage> _save(
    String originalPath, {
    required String projectId,
    required int sequence,
    required String providerName,
  }) {
    return _capturePageUseCase.processCapture(
      capture: StillCapture(
        originalImagePath: originalPath,
        detectedQuad: null,
        qualityScore: 0.8,
        warnings: const {},
        capturedAtMs: DateTime.now().millisecondsSinceEpoch,
        providerInfo: ProviderInfo(
          providerName: providerName,
          adapterVersion: '1.0.0',
        ),
      ),
      projectId: projectId,
      sequence: sequence,
      keepOriginal: true,
    );
  }
}
