import 'package:bookscanner/data/repositories/project_repository_impl.dart';
import 'package:bookscanner/domain/models/project.dart';
import 'package:bookscanner/domain/repositories/project_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_database.dart';

void main() {
  late ProjectRepositoryImpl repository;

  setUp(() async {
    final db = await openTestDatabase();
    repository = ProjectRepositoryImpl(db);
  });

  test('createProject persists and is retrievable', () async {
    final project = await repository.createProject(
      type: ProjectType.document,
      title: 'My Doc',
    );

    final fetched = await repository.getProject(project.id);
    expect(fetched, isNotNull);
    expect(fetched!.title, 'My Doc');
    expect(fetched.type, ProjectType.document);
    expect(fetched.pageOrder, isEmpty);
  });

  test('renameProject updates title', () async {
    final project = await repository.createProject(
      type: ProjectType.book,
      title: 'Old Title',
    );
    await repository.renameProject(project.id, 'New Title');
    final fetched = await repository.getProject(project.id);
    expect(fetched!.title, 'New Title');
  });

  test('moveToTrash then restoreFromTrash round-trips', () async {
    final project = await repository.createProject(
      type: ProjectType.document,
      title: 'Trash me',
    );
    await repository.moveToTrash(project.id);

    final visibleQuery = repository.watchProjects(const ProjectQuery());
    final visible = await visibleQuery.first;
    expect(visible.any((p) => p.id == project.id), isFalse);

    final trashedQuery = repository.watchProjects(
      const ProjectQuery(includeTrashed: true),
    );
    final trashed = await trashedQuery.first;
    expect(trashed.any((p) => p.id == project.id), isTrue);

    await repository.restoreFromTrash(project.id);
    final restored = await repository.getProject(project.id);
    expect(restored!.isTrashed, isFalse);
  });

  test('deletePermanently removes the row', () async {
    final project = await repository.createProject(
      type: ProjectType.document,
      title: 'Bye',
    );
    await repository.deletePermanently(project.id);
    expect(await repository.getProject(project.id), isNull);
  });

  test('watchProjects filters by search text', () async {
    await repository.createProject(
      type: ProjectType.document,
      title: 'Alpha report',
    );
    await repository.createProject(
      type: ProjectType.document,
      title: 'Beta invoice',
    );

    final results = await repository
        .watchProjects(const ProjectQuery(searchText: 'alpha'))
        .first;
    expect(results, hasLength(1));
    expect(results.first.title, 'Alpha report');
  });

  test('toggleFavorite via updateProject persists', () async {
    final project = await repository.createProject(
      type: ProjectType.document,
      title: 'Fav me',
    );
    await repository.updateProject(project.copyWith(isFavorite: true));
    final fetched = await repository.getProject(project.id);
    expect(fetched!.isFavorite, isTrue);
  });
}
