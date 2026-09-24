import 'package:bookscanner/domain/models/project.dart';
import 'package:bookscanner/domain/models/scan_page.dart';
import 'package:bookscanner/domain/repositories/page_repository.dart';
import 'package:bookscanner/ui/features/library/view_models/library_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_project_repository.dart';

class _FakePageRepository implements PageRepository {
  final pages = <String, ScanPage>{};

  @override
  Future<ScanPage?> getPage(String pageId) async => pages[pageId];

  @override
  Future<void> addPage(ScanPage page) async => pages[page.id] = page;

  @override
  Future<void> updatePage(ScanPage page) async => pages[page.id] = page;

  @override
  Future<List<ScanPage>> getPages(String projectId) async =>
      pages.values.where((p) => p.projectId == projectId).toList();

  @override
  Future<void> deletePage(String pageId) async {}

  @override
  Future<void> duplicatePage(String pageId) async {}

  @override
  Future<void> reorderPages(String projectId, List<String> order) async {}

  @override
  Stream<List<ScanPage>> watchPages(String projectId) => const Stream.empty();
}

void main() {
  test('loads the first page thumbnail path for each project', () async {
    final projects = FakeProjectRepository();
    final now = DateTime.now();
    projects.seed([
      Project(
        id: 'p1',
        type: ProjectType.document,
        title: 'Tax Forms',
        metadata: const ProjectMetadata(),
        pageOrder: const ['page1'],
        createdAt: now,
        updatedAt: now,
        processingState: ProcessingState.idle,
      ),
    ]);
    final pages = _FakePageRepository();
    await pages.addPage(
      const ScanPage(
        id: 'page1',
        projectId: 'p1',
        sequence: 0,
        originalImagePath: '/tmp/original.jpg',
        thumbnailPath: '/tmp/thumb.jpg',
        status: PageStatus.ready,
      ),
    );
    final viewModel = LibraryViewModel(
      projectRepository: projects,
      pageRepository: pages,
    );
    addTearDown(viewModel.dispose);

    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(viewModel.thumbnailFor('p1'), '/tmp/thumb.jpg');
  });

  test('falls back to the original image when no thumbnail exists', () async {
    final projects = FakeProjectRepository();
    final now = DateTime.now();
    projects.seed([
      Project(
        id: 'p1',
        type: ProjectType.document,
        title: 'Tax Forms',
        metadata: const ProjectMetadata(),
        pageOrder: const ['page1'],
        createdAt: now,
        updatedAt: now,
        processingState: ProcessingState.idle,
      ),
    ]);
    final pages = _FakePageRepository();
    await pages.addPage(
      const ScanPage(
        id: 'page1',
        projectId: 'p1',
        sequence: 0,
        originalImagePath: '/tmp/original.jpg',
        status: PageStatus.ready,
      ),
    );
    final viewModel = LibraryViewModel(
      projectRepository: projects,
      pageRepository: pages,
    );
    addTearDown(viewModel.dispose);

    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(viewModel.thumbnailFor('p1'), '/tmp/original.jpg');
  });

  test('counts documents, books, and pages from the project list', () async {
    final projects = FakeProjectRepository();
    final now = DateTime.now();
    projects.seed([
      Project(
        id: 'p1',
        type: ProjectType.document,
        title: 'Tax Forms',
        metadata: const ProjectMetadata(),
        pageOrder: const ['a', 'b'],
        createdAt: now,
        updatedAt: now,
        processingState: ProcessingState.idle,
      ),
      Project(
        id: 'p2',
        type: ProjectType.book,
        title: 'Novel Scan',
        metadata: const ProjectMetadata(),
        pageOrder: const ['c'],
        createdAt: now,
        updatedAt: now,
        processingState: ProcessingState.idle,
      ),
    ]);
    final viewModel = LibraryViewModel(projectRepository: projects);
    addTearDown(viewModel.dispose);

    await Future<void>.delayed(Duration.zero);
    expect(viewModel.documentCount, 1);
    expect(viewModel.bookCount, 1);
    expect(viewModel.pageCount, 3);
  });
}
