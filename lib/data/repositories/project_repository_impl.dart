import 'dart:async';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/project.dart';
import '../../domain/repositories/project_repository.dart';
import '../services/local/database_service.dart';
import '../services/local/json_codec_helpers.dart';

class ProjectRepositoryImpl implements ProjectRepository {
  ProjectRepositoryImpl(this._databaseService);

  final DatabaseService _databaseService;
  final _changes = StreamController<void>.broadcast();
  static const _uuid = Uuid();

  Database get _db => _databaseService.db;

  @override
  Stream<List<Project>> watchProjects(ProjectQuery query) async* {
    yield await _queryProjects(query);
    await for (final _ in _changes.stream) {
      yield await _queryProjects(query);
    }
  }

  @override
  Stream<Project?> watchProject(String id) async* {
    yield await getProject(id);
    await for (final _ in _changes.stream) {
      yield await getProject(id);
    }
  }

  Future<List<Project>> _queryProjects(ProjectQuery query) async {
    final where = <String>[];
    final args = <Object?>[];

    where.add('is_trashed = ?');
    args.add(query.includeTrashed ? 1 : 0);

    if (query.folderId != null) {
      where.add('folder_id = ?');
      args.add(query.folderId);
    }
    if (query.favoritesOnly) {
      where.add('is_favorite = 1');
    }
    if (query.searchText != null && query.searchText!.trim().isNotEmpty) {
      where.add('title LIKE ?');
      args.add('%${query.searchText!.trim()}%');
    }

    final orderColumn = switch (query.sortField) {
      ProjectSortField.updatedAt => 'updated_at',
      ProjectSortField.createdAt => 'created_at',
      ProjectSortField.title => 'title',
      ProjectSortField.pageCount => 'updated_at',
    };

    final rows = await _db.query(
      'projects',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: '$orderColumn ${query.descending ? 'DESC' : 'ASC'}',
    );

    var projects = rows.map(_fromRow).toList();

    if (query.tags.isNotEmpty) {
      projects = projects
          .where((p) => query.tags.every((t) => p.metadata.tags.contains(t)))
          .toList();
    }

    return projects;
  }

  @override
  Future<Project?> getProject(String id) async {
    final rows = await _db.query('projects', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  @override
  Future<Project> createProject({
    required ProjectType type,
    required String title,
  }) async {
    final now = DateTime.now();
    final project = Project(
      id: _uuid.v4(),
      type: type,
      title: title,
      metadata: const ProjectMetadata(),
      pageOrder: const [],
      createdAt: now,
      updatedAt: now,
      processingState: ProcessingState.idle,
    );
    await _db.insert('projects', _toRow(project));
    _changes.add(null);
    return project;
  }

  @override
  Future<void> updateProject(Project project) async {
    await _db.update(
      'projects',
      _toRow(project),
      where: 'id = ?',
      whereArgs: [project.id],
    );
    _changes.add(null);
  }

  @override
  Future<void> moveToTrash(String id) async {
    await _db.update(
      'projects',
      {'is_trashed': 1, 'trashed_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
    _changes.add(null);
  }

  @override
  Future<void> restoreFromTrash(String id) async {
    await _db.update(
      'projects',
      {'is_trashed': 0, 'trashed_at': null},
      where: 'id = ?',
      whereArgs: [id],
    );
    _changes.add(null);
  }

  @override
  Future<void> deletePermanently(String id) async {
    await _db.delete('projects', where: 'id = ?', whereArgs: [id]);
    _changes.add(null);
  }

  @override
  Future<void> renameProject(String id, String title) async {
    await _db.update(
      'projects',
      {'title': title, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
    _changes.add(null);
  }

  static Map<String, Object?> _toRow(Project project) => {
    'id': project.id,
    'type': project.type.name,
    'title': project.title,
    'author': project.metadata.author,
    'language': project.metadata.language,
    'edition': project.metadata.edition,
    'isbn': project.metadata.isbn,
    'tags': JsonCodecHelpers.encodeStringList(project.metadata.tags),
    'notes': project.metadata.notes,
    'starting_page_number': project.metadata.startingPageNumber,
    'page_order_direction': project.metadata.pageOrderDirection.name,
    'page_order': JsonCodecHelpers.encodeStringList(project.pageOrder),
    'created_at': project.createdAt.millisecondsSinceEpoch,
    'updated_at': project.updatedAt.millisecondsSinceEpoch,
    'processing_state': project.processingState.name,
    'folder_id': project.folderId,
    'is_favorite': project.isFavorite ? 1 : 0,
    'is_trashed': project.isTrashed ? 1 : 0,
    'trashed_at': project.trashedAt?.millisecondsSinceEpoch,
  };

  static Project _fromRow(Map<String, Object?> row) => Project(
    id: row['id']! as String,
    type: ProjectType.values.byName(row['type']! as String),
    title: row['title']! as String,
    metadata: ProjectMetadata(
      author: row['author'] as String?,
      language: row['language']! as String,
      edition: row['edition'] as String?,
      isbn: row['isbn'] as String?,
      tags: JsonCodecHelpers.decodeStringList(row['tags'] as String?),
      notes: row['notes'] as String?,
      startingPageNumber: row['starting_page_number']! as int,
      pageOrderDirection: PageOrderDirection.values.byName(
        row['page_order_direction']! as String,
      ),
    ),
    pageOrder: JsonCodecHelpers.decodeStringList(row['page_order'] as String?),
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at']! as int),
    processingState: ProcessingState.values.byName(
      row['processing_state']! as String,
    ),
    folderId: row['folder_id'] as String?,
    isFavorite: (row['is_favorite']! as int) == 1,
    isTrashed: (row['is_trashed']! as int) == 1,
    trashedAt: row['trashed_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row['trashed_at']! as int),
  );
}
