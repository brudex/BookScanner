import 'dart:io';

import '../../domain/repositories/page_repository.dart';
import '../../domain/repositories/project_repository.dart';
import 'di/service_locator.dart';

/// Deletes every captured page image for [projectId], then removes the
/// project. Call when the user backs out of Capture/crop/filters before
/// finishing Save / "Name this scan".
Future<void> discardUnsavedCapture(
  String projectId, {
  PageRepository? pageRepository,
  ProjectRepository? projectRepository,
}) async {
  final pagesRepo = pageRepository ?? locator<PageRepository>();
  final projects = projectRepository ?? locator<ProjectRepository>();
  final pages = await pagesRepo.getPages(projectId);
  for (final page in pages) {
    for (final path in [
      page.originalImagePath,
      page.processedImagePath,
      page.thumbnailPath,
    ]) {
      if (path == null) continue;
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    await pagesRepo.deletePage(page.id);
  }
  await projects.deletePermanently(projectId);
}
