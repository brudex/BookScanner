import '../models/folder.dart';

abstract interface class FolderRepository {
  Stream<List<Folder>> watchFolders();

  Future<Folder> createFolder(String name, {String? parentId});

  Future<void> renameFolder(String id, String name);

  Future<void> deleteFolder(String id);

  Stream<List<Tag>> watchTags();

  Future<Tag> createTag(String name);

  Future<void> deleteTag(String id);
}
