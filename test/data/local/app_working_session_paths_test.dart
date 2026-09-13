import 'dart:io';

import 'package:bookscanner/data/services/local/app_paths.dart';
import 'package:bookscanner/data/services/local/app_working_session_paths.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../fakes/fake_path_provider_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmpDir;
  late AppWorkingSessionPaths workingPaths;

  setUpAll(() async {
    tmpDir = await Directory.systemTemp.createTemp(
      'app_working_session_paths_test_',
    );
    PathProviderPlatform.instance = FakePathProviderPlatform(tmpDir);
    final appPaths = await AppPaths.instance();
    workingPaths = AppWorkingSessionPaths(appPaths);
  });

  tearDownAll(() async {
    if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
  });

  test(
    'pagePathFor returns stable, distinct paths per (sessionId, pageId)',
    () {
      final a1 = workingPaths.pagePathFor('session-a', 'page-1', ext: 'png');
      final a1Again = workingPaths.pagePathFor(
        'session-a',
        'page-1',
        ext: 'png',
      );
      final a2 = workingPaths.pagePathFor('session-a', 'page-2', ext: 'png');
      final b1 = workingPaths.pagePathFor('session-b', 'page-1', ext: 'png');

      expect(a1, a1Again);
      expect(a1, isNot(a2));
      expect(a1, isNot(b1));
      expect(Directory(File(a1).parent.path).existsSync(), isTrue);
    },
  );

  test(
    'clearSession deletes every scratch file for that session and is idempotent',
    () async {
      final path = workingPaths.pagePathFor('session-a', 'page-1', ext: 'png');
      await File(path).writeAsBytes([1, 2, 3]);
      expect(File(path).existsSync(), isTrue);

      await workingPaths.clearSession('session-a');
      expect(File(path).existsSync(), isFalse);

      // Idempotent: clearing again (or clearing a session that never existed)
      // must not throw.
      await workingPaths.clearSession('session-a');
      await workingPaths.clearSession('never-existed');
    },
  );

  test('clearSession does not touch other sessions', () async {
    final pathA = workingPaths.pagePathFor('session-a', 'page-1', ext: 'png');
    final pathB = workingPaths.pagePathFor('session-b', 'page-1', ext: 'png');
    await File(pathA).writeAsBytes([1]);
    await File(pathB).writeAsBytes([2]);

    await workingPaths.clearSession('session-a');

    expect(File(pathA).existsSync(), isFalse);
    expect(File(pathB).existsSync(), isTrue);
  });
}
