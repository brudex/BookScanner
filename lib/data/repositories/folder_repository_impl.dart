import 'dart:async';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/folder.dart';
import '../../domain/repositories/folder_repository.dart';
import '../services/local/database_service.dart';

class FolderRepositoryImpl implements FolderRepository {
  FolderRepositoryImpl(this._databaseService);

  final DatabaseService _databaseService;
  final _folderChanges = StreamController<void>.broadcast();
  final _tagChanges = StreamController<void>.broadcast();
  static const _uuid = Uuid();

  Database get _db => _databaseService.db;

  @override
  Stream<List<Folder>> watchFolders() async* {
    yield await _listFolders();
    await for (final _ in _folderChanges.stream) {
      yield await _listFolders();
    }
  }

  Future<List<Folder>> _listFolders() async {
    final rows = await _db.query('folders', orderBy: 'name ASC');
    return rows
        .map(
          (r) => Folder(
            id: r['id']! as String,
            name: r['name']! as String,
            parentId: r['parent_id'] as String?,
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              r['created_at']! as int,
            ),
          ),
        )
        .toList();
  }

  @override
  Future<Folder> createFolder(String name, {String? parentId}) async {
    final folder = Folder(
      id: _uuid.v4(),
      name: name,
      parentId: parentId,
      createdAt: DateTime.now(),
    );
    await _db.insert('folders', {
      'id': folder.id,
      'name': folder.name,
      'parent_id': folder.parentId,
      'created_at': folder.createdAt.millisecondsSinceEpoch,
    });
    _folderChanges.add(null);
    return folder;
  }

  @override
  Future<void> renameFolder(String id, String name) async {
    await _db.update(
      'folders',
      {'name': name},
      where: 'id = ?',
      whereArgs: [id],
    );
    _folderChanges.add(null);
  }

  @override
  Future<void> deleteFolder(String id) async {
    await _db.delete('folders', where: 'id = ?', whereArgs: [id]);
    await _db.update(
      'projects',
      {'folder_id': null},
      where: 'folder_id = ?',
      whereArgs: [id],
    );
    _folderChanges.add(null);
  }

  @override
  Stream<List<Tag>> watchTags() async* {
    yield await _listTags();
    await for (final _ in _tagChanges.stream) {
      yield await _listTags();
    }
  }

  Future<List<Tag>> _listTags() async {
    final rows = await _db.query('tags', orderBy: 'name ASC');
    return rows
        .map((r) => Tag(id: r['id']! as String, name: r['name']! as String))
        .toList();
  }

  @override
  Future<Tag> createTag(String name) async {
    final tag = Tag(id: _uuid.v4(), name: name);
    await _db.insert('tags', {
      'id': tag.id,
      'name': tag.name,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    _tagChanges.add(null);
    return tag;
  }

  @override
  Future<void> deleteTag(String id) async {
    await _db.delete('tags', where: 'id = ?', whereArgs: [id]);
    _tagChanges.add(null);
  }
}
