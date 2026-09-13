import '../models/scan_page.dart';

/// Domain-facing source of truth for [ScanPage] persistence. Every page is
/// persisted immediately after capture and metadata changes are written
/// synchronously so an interrupted session can always resume (SPEC 6.3, 9.1).
abstract interface class PageRepository {
  Stream<List<ScanPage>> watchPages(String projectId);

  Future<List<ScanPage>> getPages(String projectId);

  Future<ScanPage?> getPage(String pageId);

  Future<void> addPage(ScanPage page);

  Future<void> updatePage(ScanPage page);

  /// Reorders pages within a project; also updates [Project.pageOrder].
  Future<void> reorderPages(String projectId, List<String> newPageIdOrder);

  Future<void> deletePage(String pageId);

  Future<void> duplicatePage(String pageId);
}
