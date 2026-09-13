import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../domain/repositories/page_path_allocator.dart';

/// Central owner of on-disk layout for all app-managed files. Full-resolution
/// page images are stored as files; thumbnails are generated separately
/// (SPEC 9.1). Nothing here is synced to iCloud/Android auto-backup by
/// default so private scans are not silently uploaded.
class AppPaths implements PagePathAllocator {
  AppPaths._(this._root);

  final Directory _root;

  static AppPaths? _instance;

  static Future<AppPaths> instance() async {
    if (_instance != null) return _instance!;
    final support = await getApplicationSupportDirectory();
    final root = Directory(p.join(support.path, 'bookscanner'));
    await root.create(recursive: true);
    final self = AppPaths._(root);
    await self._ensureSubdirs();
    _instance = self;
    return self;
  }

  Directory get root => _root;
  Directory get originalsDir => Directory(p.join(_root.path, 'originals'));
  Directory get processedDir => Directory(p.join(_root.path, 'processed'));
  Directory get thumbnailsDir => Directory(p.join(_root.path, 'thumbnails'));
  Directory get exportsDir => Directory(p.join(_root.path, 'exports'));
  Directory get tmpDir => Directory(p.join(_root.path, 'tmp'));
  Directory get databaseDir => Directory(p.join(_root.path, 'db'));

  Future<void> _ensureSubdirs() async {
    for (final dir in [
      originalsDir,
      processedDir,
      thumbnailsDir,
      exportsDir,
      tmpDir,
      databaseDir,
    ]) {
      await dir.create(recursive: true);
    }
  }

  @override
  String originalPathFor(String pageId, {String ext = 'jpg'}) =>
      p.join(originalsDir.path, '$pageId.$ext');

  @override
  String processedPathFor(String pageId, {String ext = 'jpg'}) =>
      p.join(processedDir.path, '$pageId.$ext');

  @override
  String thumbnailPathFor(String pageId) =>
      p.join(thumbnailsDir.path, '$pageId.jpg');

  @override
  String exportPathFor(String jobId, String extension) =>
      p.join(exportsDir.path, '$jobId.$extension');

  String tmpPathFor(String name) => p.join(tmpDir.path, name);

  /// Clears the tmp working directory. Safe to call after export
  /// success/cancellation; never touches originals/processed (SPEC 11).
  Future<void> clearTmp() async {
    if (await tmpDir.exists()) {
      await tmpDir.delete(recursive: true);
    }
    await tmpDir.create(recursive: true);
  }
}
