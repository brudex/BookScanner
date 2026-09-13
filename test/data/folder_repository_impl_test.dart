import 'package:bookscanner/data/repositories/folder_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_database.dart';

void main() {
  late FolderRepositoryImpl repository;

  setUp(() async {
    final db = await openTestDatabase();
    repository = FolderRepositoryImpl(db);
  });

  test('createFolder then watchFolders lists it', () async {
    await repository.createFolder('Receipts');
    final folders = await repository.watchFolders().first;
    expect(folders.map((f) => f.name), contains('Receipts'));
  });

  test('renameFolder updates name', () async {
    final folder = await repository.createFolder('Old');
    await repository.renameFolder(folder.id, 'New');
    final folders = await repository.watchFolders().first;
    expect(folders.single.name, 'New');
  });

  test('deleteFolder removes it', () async {
    final folder = await repository.createFolder('Temp');
    await repository.deleteFolder(folder.id);
    final folders = await repository.watchFolders().first;
    expect(folders, isEmpty);
  });

  test('createTag ignores duplicate names', () async {
    await repository.createTag('receipts');
    await repository.createTag('receipts');
    final tags = await repository.watchTags().first;
    expect(tags.where((t) => t.name == 'receipts'), hasLength(1));
  });
}
