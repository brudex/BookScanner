import 'dart:io';

import 'package:bookscanner/data/services/local/database_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

var _testDbCounter = 0;

/// Real SQLite database (via sqflite_common_ffi) for repository unit tests —
/// exercises the actual SQL schema and queries, not a mock. Each call gets
/// its own temp file: sqflite's global factory caches open connections by
/// path, so reusing `inMemoryDatabasePath` (':memory:') across tests would
/// silently hand every test the *same* connection and leak state between
/// them.
Future<DatabaseService> openTestDatabase() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  _testDbCounter += 1;
  final path = p.join(
    Directory.systemTemp.path,
    'bookscanner_test_${DateTime.now().microsecondsSinceEpoch}_$_testDbCounter.db',
  );
  return DatabaseService.open(overridePath: path);
}
