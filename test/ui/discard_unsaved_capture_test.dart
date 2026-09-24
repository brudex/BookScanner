import 'dart:io';

import 'package:bookscanner/domain/models/project.dart';
import 'package:bookscanner/domain/models/scan_page.dart';
import 'package:bookscanner/domain/repositories/page_repository.dart';
import 'package:bookscanner/ui/core/discard_unsaved_capture.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'fakes/fake_project_repository.dart';

class _FakePages implements PageRepository {
  final pages = <String, ScanPage>{};

  @override
  Future<ScanPage?> getPage(String pageId) async => pages[pageId];

  @override
  Future<void> addPage(ScanPage page) async => pages[page.id] = page;

  @override
  Future<void> updatePage(ScanPage page) async => pages[page.id] = page;

  @override
  Future<List<ScanPage>> getPages(String projectId) async =>
      pages.values.where((page) => page.projectId == projectId).toList();

  @override
  Future<void> deletePage(String pageId) async => pages.remove(pageId);

  @override
  Future<void> duplicatePage(String pageId) async {}

  @override
  Future<void> reorderPages(String projectId, List<String> order) async {}

  @override
  Stream<List<ScanPage>> watchPages(String projectId) => const Stream.empty();
}

void main() {
  test('discardUnsavedCapture deletes page files and the project', () async {
    final tmp = await Directory.systemTemp.createTemp('discard_capture_');
    addTearDown(() => tmp.delete(recursive: true));

    final original = File(p.join(tmp.path, 'orig.jpg'));
    final processed = File(p.join(tmp.path, 'proc.jpg'));
    final thumb = File(p.join(tmp.path, 'thumb.jpg'));
    await original.writeAsBytes(const [1, 2, 3]);
    await processed.writeAsBytes(const [4, 5]);
    await thumb.writeAsBytes(const [6]);

    final projects = FakeProjectRepository();
    final project = await projects.createProject(
      type: ProjectType.document,
      title: 'Doc',
    );
    final pages = _FakePages();
    await pages.addPage(
      ScanPage(
        id: 'p1',
        projectId: project.id,
        sequence: 0,
        originalImagePath: original.path,
        processedImagePath: processed.path,
        thumbnailPath: thumb.path,
        status: PageStatus.ready,
      ),
    );

    await discardUnsavedCapture(
      project.id,
      pageRepository: pages,
      projectRepository: projects,
    );

    expect(await original.exists(), isFalse);
    expect(await processed.exists(), isFalse);
    expect(await thumb.exists(), isFalse);
    expect(pages.pages, isEmpty);
    expect(await projects.getProject(project.id), isNull);
  });
}
