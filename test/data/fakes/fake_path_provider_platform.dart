import 'dart:io';

import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Minimal [PathProviderPlatform] fake for VM-based tests, where no real
/// platform channel exists to answer `getApplicationSupportDirectory`.
class FakePathProviderPlatform extends PathProviderPlatform {
  FakePathProviderPlatform(this._root);

  final Directory _root;

  @override
  Future<String?> getApplicationSupportPath() async => _root.path;

  @override
  Future<String?> getTemporaryPath() async => _root.path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _root.path;

  @override
  Future<String?> getApplicationCachePath() async => _root.path;

  @override
  Future<String?> getLibraryPath() async => _root.path;
}
