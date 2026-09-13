import 'dart:io';

import 'package:image/image.dart' as img;

import '../../../domain/models/scan_page.dart';
import 'app_paths.dart';

/// Owns file-level operations (thumbnail generation, cleanup) on top of
/// [AppPaths]. Full-resolution images are never loaded entirely into memory
/// for bulk operations — only single-page thumbnail generation decodes a
/// full image, and that result is discarded immediately after encoding
/// (SPEC 6.3: handle 500+ pages without holding every full-resolution image
/// in memory).
class FileStorageService {
  FileStorageService(this._paths);

  final AppPaths _paths;

  static const int _thumbnailMaxDimension = 320;

  Future<String> generateThumbnail(
    String sourceImagePath,
    String pageId,
  ) async {
    final bytes = await File(sourceImagePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw StateError('Cannot decode image at $sourceImagePath');
    }
    final resized = img.copyResize(
      decoded,
      width: decoded.width >= decoded.height ? _thumbnailMaxDimension : null,
      height: decoded.height > decoded.width ? _thumbnailMaxDimension : null,
    );
    final outPath = _paths.thumbnailPathFor(pageId);
    await File(outPath).writeAsBytes(img.encodeJpg(resized, quality: 80));
    return outPath;
  }

  Future<void> deletePageFiles(ScanPage page) async {
    for (final path in [
      page.originalImagePath,
      page.processedImagePath,
      page.thumbnailPath,
    ]) {
      if (path == null) continue;
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }

  Future<int> fileSizeBytes(String path) async {
    final file = File(path);
    if (!await file.exists()) return 0;
    return file.length();
  }

  AppPaths get paths => _paths;
}
