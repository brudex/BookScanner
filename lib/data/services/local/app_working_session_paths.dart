import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../domain/repositories/working_session_path_allocator.dart';
import 'app_paths.dart';

/// Stores multi-source page-composition scratch files under
/// `AppPaths.tmpDir/working-sessions/<sessionId>/` — nested inside the
/// existing tmp directory rather than a new top-level one, since it's the
/// same "safe to wipe, never a real page/export artifact" storage class
/// `AppPaths.clearTmp()` already manages in bulk.
class AppWorkingSessionPaths implements WorkingSessionPathAllocator {
  AppWorkingSessionPaths(this._paths);

  final AppPaths _paths;

  Directory _sessionDir(String sessionId) =>
      Directory(p.join(_paths.tmpDir.path, 'working-sessions', sessionId));

  @override
  String pagePathFor(String sessionId, String pageId, {required String ext}) {
    final dir = _sessionDir(sessionId)..createSync(recursive: true);
    return p.join(dir.path, '$pageId.$ext');
  }

  @override
  Future<void> clearSession(String sessionId) async {
    final dir = _sessionDir(sessionId);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}
