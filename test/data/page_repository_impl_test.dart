import 'dart:io';

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

  test('deletePage keeps reading order and closes the sequence gap', () async {
    await pageRepository.addPage(buildPage('p1', 0));
    await pageRepository.addPage(buildPage('p2', 1));
    await pageRepository.addPage(buildPage('p3', 2));
    await pageRepository.addPage(buildPage('p4', 3));
    await pageRepository.reorderPages(projectId, ['p4', 'p3', 'p2', 'p1']);

    await pageRepository.deletePage('p3');

    final pages = await pageRepository.getPages(projectId);
    expect(pages.map((p) => p.id), ['p4', 'p2', 'p1']);
    expect(pages.map((p) => p.sequence), [0, 1, 2]);
    final project = await projectRepository.getProject(projectId);
    expect(project!.pageOrder, ['p4', 'p2', 'p1']);
  });

  test('duplicatePage inserts the copy right after its original', () async {
    await pageRepository.addPage(buildPage('p1', 0));
    await pageRepository.addPage(buildPage('p2', 1));
    await pageRepository.addPage(buildPage('p3', 2));

    await pageRepository.duplicatePage('p2');

    final pages = await pageRepository.getPages(projectId);
    expect(pages, hasLength(4));
    expect(pages[0].id, 'p1');
    expect(pages[1].id, 'p2');
    expect(pages[2].id, startsWith('p2-copy-'));
    expect(pages[3].id, 'p3');
    expect(pages.map((p) => p.sequence), [0, 1, 2, 3]);
    final project = await projectRepository.getProject(projectId);
    expect(project!.pageOrder, pages.map((p) => p.id).toList());
  });

  group('deletePage file cleanup', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('page_delete_files_');
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    String touch(String name) {
      final file = File('${dir.path}/$name')..writeAsBytesSync([1, 2, 3]);
      return file.path;
    }

    ScanPage pageWithFiles(String id, int sequence) => ScanPage(
      id: id,
      projectId: projectId,
      sequence: sequence,
      originalImagePath: touch('$id-original.jpg'),
      processedImagePath: touch('$id.jpg'),
      thumbnailPath: touch('$id-thumb.jpg'),
      status: PageStatus.ready,
    );

    /// Cleanup runs in the background after deletePage returns.
    Future<void> waitFor(bool Function() condition) async {
      for (var i = 0; i < 100 && !condition(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    test('removes the deleted page\'s images and its filter preview', () async {
      final page = pageWithFiles('p1', 0);
      final preview = touch('p1_preview.jpg');
      await pageRepository.addPage(page);

      await pageRepository.deletePage('p1');

      final paths = [
        page.originalImagePath,
        page.processedImagePath!,
        page.thumbnailPath!,
        preview,
      ];
      await waitFor(() => paths.every((path) => !File(path).existsSync()));
      for (final path in paths) {
        expect(File(path).existsSync(), isFalse, reason: path);
      }
    });

    test('keeps files that a duplicate still uses', () async {
      final page = pageWithFiles('p1', 0);
      await pageRepository.addPage(page);
      await pageRepository.duplicatePage('p1');

      await pageRepository.deletePage('p1');
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(File(page.originalImagePath).existsSync(), isTrue);
      expect(File(page.processedImagePath!).existsSync(), isTrue);
      expect(File(page.thumbnailPath!).existsSync(), isTrue);
      final pages = await pageRepository.getPages(projectId);
      expect(pages.single.id, startsWith('p1-copy-'));
    });

    test('a file that cannot be deleted does not throw or block', () async {
      // A non-empty directory at the image path makes File.delete fail.
      final blocked = Directory('${dir.path}/blocked.jpg')..createSync();
      File('${blocked.path}/inner').writeAsBytesSync([1]);
      await pageRepository.addPage(
        ScanPage(
          id: 'p1',
          projectId: projectId,
          sequence: 0,
          originalImagePath: blocked.path,
          processedImagePath: '${dir.path}/missing.jpg',
          status: PageStatus.ready,
        ),
      );

      await pageRepository.deletePage('p1');
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(await pageRepository.getPage('p1'), isNull);
      expect(blocked.existsSync(), isTrue);
    });
  });
}
