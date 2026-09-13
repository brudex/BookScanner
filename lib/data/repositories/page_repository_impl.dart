import 'dart:async';
import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../domain/models/capture_models.dart';
import '../../domain/models/geometry.dart';
import '../../domain/models/provider_info.dart';
import '../../domain/models/scan_page.dart';
import '../../domain/repositories/page_repository.dart';
import '../services/local/database_service.dart';
import '../services/local/json_codec_helpers.dart';

class PageRepositoryImpl implements PageRepository {
  PageRepositoryImpl(this._databaseService);

  final DatabaseService _databaseService;
  final _changes = StreamController<String>.broadcast();

  Database get _db => _databaseService.db;

  @override
  Stream<List<ScanPage>> watchPages(String projectId) async* {
    yield await getPages(projectId);
    await for (final changedProjectId in _changes.stream) {
      if (changedProjectId == projectId) {
        yield await getPages(projectId);
      }
    }
  }

  @override
  Future<List<ScanPage>> getPages(String projectId) async {
    final rows = await _db.query(
      'pages',
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'sequence ASC',
    );
    return rows.map(_fromRow).toList();
  }

  @override
  Future<ScanPage?> getPage(String pageId) async {
    final rows = await _db.query('pages', where: 'id = ?', whereArgs: [pageId]);
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  @override
  Future<void> addPage(ScanPage page) async {
    await _db.insert('pages', _toRow(page));
    await _appendToProjectOrder(page.projectId, page.id);
    _changes.add(page.projectId);
  }

  @override
  Future<void> updatePage(ScanPage page) async {
    await _db.update(
      'pages',
      _toRow(page),
      where: 'id = ?',
      whereArgs: [page.id],
    );
    _changes.add(page.projectId);
  }

  @override
  Future<void> reorderPages(
    String projectId,
    List<String> newPageIdOrder,
  ) async {
    await _db.transaction((txn) async {
      for (var i = 0; i < newPageIdOrder.length; i++) {
        await txn.update(
          'pages',
          {'sequence': i},
          where: 'id = ?',
          whereArgs: [newPageIdOrder[i]],
        );
      }
      await txn.update(
        'projects',
        {
          'page_order': JsonCodecHelpers.encodeStringList(newPageIdOrder),
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [projectId],
      );
    });
    _changes.add(projectId);
  }

  @override
  Future<void> deletePage(String pageId) async {
    final page = await getPage(pageId);
    if (page == null) return;
    await _db.delete('pages', where: 'id = ?', whereArgs: [pageId]);
    final rows = await _db.query(
      'pages',
      where: 'project_id = ?',
      whereArgs: [page.projectId],
    );
    final remainingIds = rows.map((r) => r['id']! as String).toList();
    await _db.update(
      'projects',
      {
        'page_order': JsonCodecHelpers.encodeStringList(remainingIds),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [page.projectId],
    );
    _changes.add(page.projectId);
  }

  @override
  Future<void> duplicatePage(String pageId) async {
    final page = await getPage(pageId);
    if (page == null) return;
    final pages = await getPages(page.projectId);
    final newId = '${page.id}-copy-${DateTime.now().millisecondsSinceEpoch}';
    final copy = ScanPage(
      id: newId,
      projectId: page.projectId,
      sequence: pages.length,
      originalImagePath: page.originalImagePath,
      status: page.status,
      logicalPageLabel: page.logicalPageLabel,
      processedImagePath: page.processedImagePath,
      thumbnailPath: page.thumbnailPath,
      cropPoints: page.cropPoints,
      rotationDegrees: page.rotationDegrees,
      filter: page.filter,
      qualityScore: page.qualityScore,
    );
    await addPage(copy);
  }

  Future<void> _appendToProjectOrder(String projectId, String pageId) async {
    final rows = await _db.query(
      'projects',
      columns: ['page_order'],
      where: 'id = ?',
      whereArgs: [projectId],
    );
    if (rows.isEmpty) return;
    final order = JsonCodecHelpers.decodeStringList(
      rows.first['page_order'] as String?,
    );
    if (!order.contains(pageId)) order.add(pageId);
    await _db.update(
      'projects',
      {
        'page_order': JsonCodecHelpers.encodeStringList(order),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [projectId],
    );
  }

  static Map<String, Object?> _toRow(ScanPage page) => {
    'id': page.id,
    'project_id': page.projectId,
    'sequence': page.sequence,
    'logical_page_label': page.logicalPageLabel,
    'original_image_path': page.originalImagePath,
    'processed_image_path': page.processedImagePath,
    'thumbnail_path': page.thumbnailPath,
    'crop_points': page.cropPoints == null
        ? null
        : jsonEncode(page.cropPoints!.toJson()),
    'rotation_degrees': page.rotationDegrees,
    'filter': page.filter.name,
    'brightness': page.brightness,
    'contrast': page.contrast,
    'sharpness': page.sharpness,
    'quality_score': page.qualityScore,
    'warnings': jsonEncode(page.warnings.map((w) => w.name).toList()),
    'duplicate_of_page_id': page.duplicateOfPageId,
    'likely_missing_before': page.likelyMissingBefore ? 1 : 0,
    'dismissed_warnings': JsonCodecHelpers.encodeStringList(
      page.dismissedWarnings.toList(),
    ),
    'stages': jsonEncode(
      page.stages.map(
        (stage, record) => MapEntry(stage.name, {
          'version': record.version,
          'completedAtMs': record.completedAtMs,
          'providerInfo': record.providerInfo.toJson(),
        }),
      ),
    ),
    'captured_at_ms': page.capturedAtMs,
    'spread_sibling_page_id': page.spreadSiblingPageId,
    'status': page.status.name,
  };

  static ScanPage _fromRow(Map<String, Object?> row) {
    final cropJson = row['crop_points'] as String?;
    final stagesJson =
        jsonDecode(row['stages'] as String? ?? '{}') as Map<String, Object?>;
    return ScanPage(
      id: row['id']! as String,
      projectId: row['project_id']! as String,
      sequence: row['sequence']! as int,
      logicalPageLabel: row['logical_page_label'] as String?,
      originalImagePath: row['original_image_path']! as String,
      processedImagePath: row['processed_image_path'] as String?,
      thumbnailPath: row['thumbnail_path'] as String?,
      cropPoints: cropJson == null
          ? null
          : Quad.fromJson(
              (jsonDecode(cropJson) as Map).cast<String, Object?>(),
            ),
      rotationDegrees: row['rotation_degrees']! as int,
      filter: PageFilter.values.byName(row['filter']! as String),
      brightness: (row['brightness']! as num).toDouble(),
      contrast: (row['contrast']! as num).toDouble(),
      sharpness: (row['sharpness']! as num).toDouble(),
      qualityScore: (row['quality_score'] as num?)?.toDouble(),
      warnings: JsonCodecHelpers.decodeStringList(
        row['warnings'] as String?,
      ).map((w) => QualityWarning.values.byName(w)).toSet(),
      duplicateOfPageId: row['duplicate_of_page_id'] as String?,
      likelyMissingBefore: (row['likely_missing_before']! as int) == 1,
      dismissedWarnings: JsonCodecHelpers.decodeStringList(
        row['dismissed_warnings'] as String?,
      ).toSet(),
      stages: stagesJson.map((key, value) {
        final v = (value as Map).cast<String, Object?>();
        return MapEntry(
          PipelineStage.values.byName(key),
          StageRecord(
            version: v['version']! as int,
            completedAtMs: v['completedAtMs']! as int,
            providerInfo: ProviderInfo.fromJson(
              (v['providerInfo']! as Map).cast<String, Object?>(),
            ),
          ),
        );
      }),
      capturedAtMs: row['captured_at_ms'] as int?,
      spreadSiblingPageId: row['spread_sibling_page_id'] as String?,
      status: PageStatus.values.byName(row['status']! as String),
    );
  }
}
