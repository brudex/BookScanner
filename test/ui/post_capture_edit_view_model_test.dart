import 'dart:io';

import 'package:bookscanner/domain/models/geometry.dart';
import 'package:bookscanner/domain/models/project.dart';
import 'package:bookscanner/domain/models/provider_info.dart';
import 'package:bookscanner/domain/models/scan_page.dart';
import 'package:bookscanner/domain/providers/image_enhancement_provider.dart';
import 'package:bookscanner/domain/providers/page_detection_provider.dart';
import 'package:bookscanner/domain/repositories/page_path_allocator.dart';
import 'package:bookscanner/domain/repositories/page_repository.dart';
import 'package:bookscanner/domain/repositories/project_repository.dart';
import 'package:bookscanner/domain/use_cases/capture_page_use_case.dart';
import 'package:bookscanner/ui/features/page_review/view_models/post_capture_edit_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

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
  Future<void> deletePage(String pageId) async {}

  @override
  Future<void> duplicatePage(String pageId) async {}

  @override
  Future<void> reorderPages(String projectId, List<String> order) async {}

  @override
  Stream<List<ScanPage>> watchPages(String projectId) => const Stream.empty();
}

class _FakeProjects implements ProjectRepository {
  Project? project;
  final renames = <(String, String)>[];

  @override
  Future<Project?> getProject(String id) async => project;

  @override
  Future<void> renameProject(String id, String title) async {
    renames.add((id, title));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDetect implements PageDetectionProvider {
  @override
  ProviderInfo get info =>
      const ProviderInfo(providerName: 'fake', adapterVersion: '1');

  @override
  Future<Quad?> detectQuad(String imagePath) async => null;
}

class _FakeEnhance implements ImageEnhancementProvider {
  @override
  ProviderInfo get info =>
      const ProviderInfo(providerName: 'fake', adapterVersion: '1');

  @override
  Future<double> scoreQuality(String imagePath) async => 0.9;

  @override
  Future<EnhancementResult> enhance(EnhancementRequest request) async =>
      EnhancementResult(
        processedImagePath: request.outputImagePath,
        thumbnailPath: request.outputImagePath,
        qualityScore: 0.9,
        providerInfo: info,
      );
}

class _Paths implements PagePathAllocator {
  @override
  String originalPathFor(String pageId, {required String ext}) =>
      '/tmp/$pageId-o.$ext';

  @override
  String processedPathFor(String pageId, {required String ext}) =>
      '/tmp/$pageId-p.$ext';

  @override
  String thumbnailPathFor(String pageId) => '/tmp/$pageId-t.jpg';

  @override
  String exportPathFor(String jobId, String extension) =>
      '/tmp/$jobId.$extension';
}

void main() {
  test('walks pages in order and finishes after the last save', () async {
    final tmp = await Directory.systemTemp.createTemp('post_capture_edit_');
    addTearDown(() => tmp.delete(recursive: true));
    final image = img.Image(width: 40, height: 40);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    final path = p.join(tmp.path, 'a.jpg');
    await File(path).writeAsBytes(img.encodeJpg(image));

    final pages = _FakePages();
    final now = DateTime.now();
    await pages.addPage(
      ScanPage(
        id: 'p1',
        projectId: 'proj1',
        sequence: 0,
        originalImagePath: path,
        processedImagePath: path,
        status: PageStatus.ready,
        filter: PageFilter.blackAndWhite,
      ),
    );
    await pages.addPage(
      ScanPage(
        id: 'p2',
        projectId: 'proj1',
        sequence: 1,
        originalImagePath: path,
        processedImagePath: path,
        status: PageStatus.ready,
        filter: PageFilter.blackAndWhite,
      ),
    );
    final projects = _FakeProjects()
      ..project = Project(
        id: 'proj1',
        type: ProjectType.document,
        title: 'Document',
        metadata: const ProjectMetadata(),
        pageOrder: const ['p1', 'p2'],
        createdAt: now,
        updatedAt: now,
        processingState: ProcessingState.idle,
      );

    final vm = PostCaptureEditViewModel(
      projectId: 'proj1',
      pageRepository: pages,
      projectRepository: projects,
      capturePageUseCase: CapturePageUseCase(
        pageRepository: pages,
        enhancementProvider: _FakeEnhance(),
        detectionProvider: _FakeDetect(),
        fileStorage: _Paths(),
      ),
    );
    addTearDown(vm.dispose);

    await vm.initialize();
    expect(vm.index, 0);
    expect(vm.isLastPage, isFalse);

    expect(await vm.saveAndAdvance(), isTrue);
    expect(vm.index, 1);
    expect(vm.isLastPage, isTrue);
    expect(vm.finished, isFalse);

    expect(await vm.saveAndAdvance(), isTrue);
    expect(vm.finished, isTrue);
  });

  test('reloadCurrentAfterExternalEdit refreshes the editor from disk', () async {
    final tmp = await Directory.systemTemp.createTemp('post_capture_reload_');
    addTearDown(() => tmp.delete(recursive: true));
    final image = img.Image(width: 40, height: 40);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    final path = p.join(tmp.path, 'a.jpg');
    final cropped = p.join(tmp.path, 'cropped.jpg');
    await File(path).writeAsBytes(img.encodeJpg(image));
    await File(cropped).writeAsBytes(img.encodeJpg(image));

    final pages = _FakePages();
    final now = DateTime.now();
    await pages.addPage(
      ScanPage(
        id: 'p1',
        projectId: 'proj1',
        sequence: 0,
        originalImagePath: path,
        processedImagePath: path,
        status: PageStatus.ready,
        filter: PageFilter.blackAndWhite,
      ),
    );
    final projects = _FakeProjects()
      ..project = Project(
        id: 'proj1',
        type: ProjectType.document,
        title: 'Document',
        metadata: const ProjectMetadata(),
        pageOrder: const ['p1'],
        createdAt: now,
        updatedAt: now,
        processingState: ProcessingState.idle,
      );

    final vm = PostCaptureEditViewModel(
      projectId: 'proj1',
      pageRepository: pages,
      projectRepository: projects,
      capturePageUseCase: CapturePageUseCase(
        pageRepository: pages,
        enhancementProvider: _FakeEnhance(),
        detectionProvider: _FakeDetect(),
        fileStorage: _Paths(),
      ),
    );
    addTearDown(vm.dispose);
    await vm.initialize();
    expect(vm.editor?.previewImagePath, path);

    await pages.updatePage(
      (await pages.getPage('p1'))!.copyWith(processedImagePath: cropped),
    );
    await vm.reloadCurrentAfterExternalEdit();

    expect(vm.editor?.previewImagePath, cropped);
    expect(vm.editor?.showingSavedProcessed, isTrue);
  });
}
