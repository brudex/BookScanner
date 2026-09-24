import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'app_paths.dart';

/// Owns the local relational database (SPEC 9.1: "Local relational database
/// stores projects, pages, OCR blocks, metadata, and job state"). Schema
/// changes go through [_migrations] so an app update never loses a resumable
/// session.
class DatabaseService {
  DatabaseService._(this._db);

  final Database _db;
  Database get db => _db;

  static const int schemaVersion = 3;

  static Future<DatabaseService> open({String? overridePath}) async {
    final path =
        overridePath ??
        p.join((await AppPaths.instance()).databaseDir.path, 'bookscanner.db');
    final db = await openDatabase(
      path,
      version: schemaVersion,
      onCreate: (db, version) async {
        for (final statement in _createStatements) {
          await db.execute(statement);
        }
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        for (var v = oldVersion + 1; v <= newVersion; v++) {
          final migration = _migrations[v];
          if (migration != null) {
            for (final statement in migration) {
              await db.execute(statement);
            }
          }
        }
      },
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
    return DatabaseService._(db);
  }

  Future<void> close() => _db.close();

  static const List<String> _createStatements = [
    '''
    CREATE TABLE projects (
      id TEXT PRIMARY KEY,
      type TEXT NOT NULL,
      title TEXT NOT NULL,
      author TEXT,
      language TEXT NOT NULL DEFAULT 'en',
      edition TEXT,
      isbn TEXT,
      tags TEXT NOT NULL DEFAULT '[]',
      notes TEXT,
      starting_page_number INTEGER NOT NULL DEFAULT 1,
      page_order_direction TEXT NOT NULL DEFAULT 'leftToRight',
      book_scan_mode TEXT NOT NULL DEFAULT 'twoPageSpread',
      page_order TEXT NOT NULL DEFAULT '[]',
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      processing_state TEXT NOT NULL DEFAULT 'idle',
      folder_id TEXT,
      is_favorite INTEGER NOT NULL DEFAULT 0,
      is_trashed INTEGER NOT NULL DEFAULT 0,
      trashed_at INTEGER
    )
    ''',
    '''
    CREATE TABLE pages (
      id TEXT PRIMARY KEY,
      project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
      sequence INTEGER NOT NULL,
      logical_page_label TEXT,
      original_image_path TEXT NOT NULL,
      processed_image_path TEXT,
      thumbnail_path TEXT,
      crop_points TEXT,
      rotation_degrees INTEGER NOT NULL DEFAULT 0,
      fine_rotation_degrees REAL NOT NULL DEFAULT 0,
      filter TEXT NOT NULL DEFAULT 'original',
      brightness REAL NOT NULL DEFAULT 0,
      contrast REAL NOT NULL DEFAULT 0,
      sharpness REAL NOT NULL DEFAULT 0,
      threshold REAL NOT NULL DEFAULT 0.5,
      quality_score REAL,
      warnings TEXT NOT NULL DEFAULT '[]',
      duplicate_of_page_id TEXT,
      likely_missing_before INTEGER NOT NULL DEFAULT 0,
      dismissed_warnings TEXT NOT NULL DEFAULT '[]',
      stages TEXT NOT NULL DEFAULT '{}',
      captured_at_ms INTEGER,
      spread_sibling_page_id TEXT,
      status TEXT NOT NULL DEFAULT 'capturing'
    )
    ''',
    'CREATE INDEX idx_pages_project_id ON pages(project_id)',
    '''
    CREATE TABLE ocr_blocks (
      id TEXT PRIMARY KEY,
      page_id TEXT NOT NULL REFERENCES pages(id) ON DELETE CASCADE,
      bounding_polygon TEXT NOT NULL,
      text TEXT NOT NULL,
      confidence REAL NOT NULL,
      language TEXT NOT NULL,
      block_type TEXT NOT NULL,
      reading_order INTEGER NOT NULL,
      words TEXT NOT NULL DEFAULT '[]',
      corrections TEXT NOT NULL DEFAULT '[]',
      table_row INTEGER,
      table_column INTEGER,
      heading_level INTEGER
    )
    ''',
    'CREATE INDEX idx_ocr_blocks_page_id ON ocr_blocks(page_id)',
    '''
    CREATE TABLE export_jobs (
      id TEXT PRIMARY KEY,
      project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
      format TEXT NOT NULL,
      status TEXT NOT NULL,
      progress REAL NOT NULL DEFAULT 0,
      error TEXT,
      output_path TEXT,
      created_at INTEGER NOT NULL,
      completed_at INTEGER,
      pdf_options TEXT,
      markdown_options TEXT,
      docx_options TEXT
    )
    ''',
    'CREATE INDEX idx_export_jobs_project_id ON export_jobs(project_id)',
    '''
    CREATE TABLE folders (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      parent_id TEXT,
      created_at INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE tags (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL UNIQUE
    )
    ''',
    '''
    CREATE TABLE settings (
      id TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
    ''',
  ];

  /// Keyed by target schema version. Add an entry here for every future
  /// migration instead of mutating [_createStatements].
  static const Map<int, List<String>> _migrations = {
    2: [
      "ALTER TABLE projects ADD COLUMN book_scan_mode TEXT NOT NULL DEFAULT 'twoPageSpread'",
    ],
    3: [
      'ALTER TABLE pages ADD COLUMN fine_rotation_degrees REAL NOT NULL DEFAULT 0',
      'ALTER TABLE pages ADD COLUMN threshold REAL NOT NULL DEFAULT 0.5',
    ],
  };
}
