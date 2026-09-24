import '../models/project.dart';

enum ProjectSortField { updatedAt, createdAt, title, pageCount }

class ProjectQuery {
  const ProjectQuery({
    this.folderId,
    this.searchText,
    this.tags = const [],
    this.includeTrashed = false,
    this.favoritesOnly = false,
    this.sortField = ProjectSortField.updatedAt,
    this.descending = true,
  });

  final String? folderId;
  final String? searchText;
  final List<String> tags;
  final bool includeTrashed;
  final bool favoritesOnly;
  final ProjectSortField sortField;
  final bool descending;
}

/// Domain-facing source of truth for [Project] persistence (SPEC 9.1).
/// Backed by the local relational database service; never exposes raw SQL
/// rows or platform types to callers.
abstract interface class ProjectRepository {
  Stream<List<Project>> watchProjects(ProjectQuery query);

  Stream<Project?> watchProject(String id);

  /// Ids of non-trashed projects with at least one recognized OCR block
  /// whose text contains [text] (case-insensitive), for library search
  /// across scanned content (SPEC 6.8) rather than just the title.
  Future<Set<String>> projectIdsMatchingOcrText(String text);

  Future<Project?> getProject(String id);

  Future<Project> createProject({
    required ProjectType type,
    required String title,
  });

  Future<void> updateProject(Project project);

  Future<void> moveToTrash(String id);

  Future<void> restoreFromTrash(String id);

  /// Permanently deletes the project and its page files. Irreversible.
  Future<void> deletePermanently(String id);

  Future<void> renameProject(String id, String title);
}
