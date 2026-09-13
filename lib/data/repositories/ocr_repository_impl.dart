import 'dart:async';
import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/ocr_block.dart';
import '../../domain/repositories/ocr_repository.dart';
import '../services/local/database_service.dart';

class OcrRepositoryImpl implements OcrRepository {
  OcrRepositoryImpl(this._databaseService);

  final DatabaseService _databaseService;
  final _changes = StreamController<String>.broadcast();
  static const _uuid = Uuid();

  Database get _db => _databaseService.db;

  @override
  Future<List<OcrBlock>> getBlocks(String pageId) async {
    final rows = await _db.query(
      'ocr_blocks',
      where: 'page_id = ?',
      whereArgs: [pageId],
      orderBy: 'reading_order ASC',
    );
    return rows.map(_fromRow).toList();
  }

  @override
  Stream<List<OcrBlock>> watchBlocks(String pageId) async* {
    yield await getBlocks(pageId);
    await for (final changedPageId in _changes.stream) {
      if (changedPageId == pageId) yield await getBlocks(pageId);
    }
  }

  @override
  Future<void> saveBlocks(String pageId, List<OcrBlock> blocks) async {
    await _db.transaction((txn) async {
      await txn.delete('ocr_blocks', where: 'page_id = ?', whereArgs: [pageId]);
      for (final block in blocks) {
        await txn.insert('ocr_blocks', _toRow(block));
      }
    });
    _changes.add(pageId);
  }

  @override
  Future<void> correctBlock(
    String pageId,
    String blockId,
    String newText,
  ) async {
    final rows = await _db.query(
      'ocr_blocks',
      where: 'id = ?',
      whereArgs: [blockId],
    );
    if (rows.isEmpty) return;
    final block = _fromRow(rows.first);
    final corrected = block.withCorrection(
      newText,
      DateTime.now().millisecondsSinceEpoch,
    );
    await _db.update(
      'ocr_blocks',
      _toRow(corrected),
      where: 'id = ?',
      whereArgs: [blockId],
    );
    _changes.add(pageId);
  }

  @override
  Future<bool> hasOcr(String pageId) async {
    final rows = await _db.query(
      'ocr_blocks',
      columns: ['id'],
      where: 'page_id = ?',
      whereArgs: [pageId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  @override
  Future<List<String>> searchPages(String projectId, String query) async {
    if (query.trim().isEmpty) return const [];
    final rows = await _db.rawQuery(
      '''
      SELECT DISTINCT ocr_blocks.page_id, MIN(pages.sequence) AS seq
      FROM ocr_blocks
      JOIN pages ON pages.id = ocr_blocks.page_id
      WHERE pages.project_id = ? AND ocr_blocks.text LIKE ?
      GROUP BY ocr_blocks.page_id
      ORDER BY seq ASC
      ''',
      [projectId, '%${query.trim()}%'],
    );
    return rows.map((r) => r['page_id']! as String).toList();
  }

  static Map<String, Object?> _toRow(OcrBlock block) => {
    'id': block.id.isEmpty ? _uuid.v4() : block.id,
    'page_id': block.pageId,
    'bounding_polygon': jsonEncode(block.boundingPolygon.toJson()),
    'text': block.text,
    'confidence': block.confidence,
    'language': block.language,
    'block_type': block.blockType.name,
    'reading_order': block.readingOrder,
    'words': jsonEncode(
      block.words
          .map(
            (w) => {
              'text': w.text,
              'boundingPolygon': w.boundingPolygon.toJson(),
              'confidence': w.confidence,
            },
          )
          .toList(),
    ),
    'corrections': jsonEncode(
      block.corrections
          .map(
            (c) => {
              'previousText': c.previousText,
              'newText': c.newText,
              'correctedAtMs': c.correctedAtMs,
            },
          )
          .toList(),
    ),
    'table_row': block.tableRow,
    'table_column': block.tableColumn,
    'heading_level': block.headingLevel,
  };

  static OcrBlock _fromRow(Map<String, Object?> row) {
    final words = (jsonDecode(row['words'] as String? ?? '[]') as List)
        .cast<Map<String, Object?>>()
        .map(
          (w) => OcrWord(
            text: w['text']! as String,
            boundingPolygon: Polygon.fromJson(
              (w['boundingPolygon']! as Map).cast<String, Object?>(),
            ),
            confidence: (w['confidence']! as num).toDouble(),
          ),
        )
        .toList();
    final corrections =
        (jsonDecode(row['corrections'] as String? ?? '[]') as List)
            .cast<Map<String, Object?>>()
            .map(
              (c) => OcrCorrection(
                previousText: c['previousText']! as String,
                newText: c['newText']! as String,
                correctedAtMs: c['correctedAtMs']! as int,
              ),
            )
            .toList();
    return OcrBlock(
      id: row['id']! as String,
      pageId: row['page_id']! as String,
      boundingPolygon: Polygon.fromJson(
        (jsonDecode(row['bounding_polygon']! as String) as Map)
            .cast<String, Object?>(),
      ),
      text: row['text']! as String,
      confidence: (row['confidence']! as num).toDouble(),
      language: row['language']! as String,
      blockType: BlockType.values.byName(row['block_type']! as String),
      readingOrder: row['reading_order']! as int,
      words: words,
      corrections: corrections,
      tableRow: row['table_row'] as int?,
      tableColumn: row['table_column'] as int?,
      headingLevel: row['heading_level'] as int?,
    );
  }
}
