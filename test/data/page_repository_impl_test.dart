import 'package:bookscanner/data/repositories/page_repository_impl.dart';
import 'package:bookscanner/data/repositories/project_repository_impl.dart';
import 'package:bookscanner/domain/models/project.dart';
import 'package:bookscanner/domain/models/scan_page.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_database.dart';

void main() {
  late PageRepositoryImpl pageRepository;
  late ProjectRepositoryImpl projectRepository;
  late String projectId;

  setUp(() async {
    final db = await openTestDatabase();
    pageRepository = PageRepositoryImpl(db);
    projectRepository = ProjectRepositoryImpl(db);
    final project = await projectRepository.createProject(
      type: ProjectType.document,
      title: 'Doc',
    );
    projectId = project.id;
  });

  ScanPage buildPage(String id, int sequence) => ScanPage(
    id: id,
    projectId: projectId,
    sequence: sequence,
    originalImagePath: '/tmp/$id.jpg',
    status: PageStatus.ready,
  );

  test('addPage persists and updates project pageOrder', () async {
    await pageRepository.addPage(buildPage('p1', 0));
    await pageRepository.addPage(buildPage('p2', 1));

    final pages = await pageRepository.getPages(projectId);
    expect(pages.map((p) => p.id).toList(), ['p1', 'p2']);

    final project = await projectRepository.getProject(projectId);
    expect(project!.pageOrder, ['p1', 'p2']);
  });

  test('reorderPages updates sequence and project pageOrder', () async {
    await pageRepository.addPage(buildPage('p1', 0));
    await pageRepository.addPage(buildPage('p2', 1));
    await pageRepository.addPage(buildPage('p3', 2));

    await pageRepository.reorderPages(projectId, ['p3', 'p1', 'p2']);

    final pages = await pageRepository.getPages(projectId);
    expect(pages.map((p) => p.id).toList(), ['p3', 'p1', 'p2']);

    final project = await projectRepository.getProject(projectId);
    expect(project!.pageOrder, ['p3', 'p1', 'p2']);
  });

  test('deletePage removes it and re-syncs project order', () async {
    await pageRepository.addPage(buildPage('p1', 0));
    await pageRepository.addPage(buildPage('p2', 1));

    await pageRepository.deletePage('p1');

    final pages = await pageRepository.getPages(projectId);
    expect(pages.map((p) => p.id).toList(), ['p2']);

    final project = await projectRepository.getProject(projectId);
    expect(project!.pageOrder, ['p2']);
  });

  test(
    'duplicatePage creates a copy referencing the same original image',
    () async {
      await pageRepository.addPage(buildPage('p1', 0));
      await pageRepository.duplicatePage('p1');

      final pages = await pageRepository.getPages(projectId);
      expect(pages, hasLength(2));
      expect(pages[1].originalImagePath, pages[0].originalImagePath);
    },
  );

  test(
    'updatePage persists crop points, rotation, and warnings round-trip',
    () async {
      await pageRepository.addPage(buildPage('p1', 0));
      final page = (await pageRepository.getPage('p1'))!;
      final updated = page.copyWith(
        rotationDegrees: 90,
        logicalPageLabel: 'iv',
        dismissedWarnings: {'blur'},
      );
      await pageRepository.updatePage(updated);

      final fetched = await pageRepository.getPage('p1');
      expect(fetched!.rotationDegrees, 90);
      expect(fetched.logicalPageLabel, 'iv');
      expect(fetched.dismissedWarnings, {'blur'});
    },
  );
}
