import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../domain/models/project.dart';
import '../../../../domain/repositories/page_repository.dart';
import '../../../../domain/repositories/project_repository.dart';

class LibraryViewModel extends ChangeNotifier {
  LibraryViewModel({
    required ProjectRepository projectRepository,
    PageRepository? pageRepository,
    String? folderId,
  }) : _projectRepository = projectRepository,
       _pageRepository = pageRepository,
       _folderId = folderId {
    _subscribe();
  }

  final ProjectRepository _projectRepository;
  final PageRepository? _pageRepository;
  StreamSubscription<List<Project>>? _subscription;
  int _thumbnailLoadId = 0;
  int _ocrSearchId = 0;

  /// Sorted, favorite/trash/folder-filtered projects straight from the
  /// repository, before the text-search filter in [_applySearch] narrows
  /// them down to [projects] -- kept separately so an async OCR-match
  /// refresh (in [_refreshOcrMatches]) can re-derive [projects] without
  /// permanently losing projects a previous, narrower search already
  /// filtered out.
  List<Project> _rawProjects = const [];

  List<Project> _projects = const [];
  List<Project> get projects => _projects;

  Map<String, String> _thumbnails = const {};
  String? thumbnailFor(String projectId) => _thumbnails[projectId];

  bool _loading = true;
  bool get loading => _loading;

  String _searchText = '';
  String get searchText => _searchText;

  bool _favoritesOnly = false;
  bool get favoritesOnly => _favoritesOnly;

  bool _includeTrashed = false;
  bool get includeTrashed => _includeTrashed;

  String? _folderId;
  String? get folderId => _folderId;

  ProjectSortField _sortField = ProjectSortField.updatedAt;
  ProjectSortField get sortField => _sortField;

  bool _descending = true;
  bool get descending => _descending;

  Set<String> _ocrMatchIds = const {};

  Object? _error;
  Object? get error => _error;

  int get documentCount =>
      _projects.where((p) => p.type == ProjectType.document).length;

  int get bookCount =>
      _projects.where((p) => p.type == ProjectType.book).length;

  int get pageCount =>
      _projects.fold<int>(0, (sum, p) => sum + p.pageOrder.length);

  void _subscribe() {
    _subscription?.cancel();
    _subscription = _projectRepository
        .watchProjects(
          ProjectQuery(
            favoritesOnly: _favoritesOnly,
            includeTrashed: _includeTrashed,
            folderId: _folderId,
            sortField: _sortField,
            descending: _descending,
          ),
        )
        .listen(
          (projects) {
            _rawProjects = _applySort(projects);
            _projects = _applySearch(_rawProjects);
            _loading = false;
            _error = null;
            notifyListeners();
            unawaited(_loadThumbnails(_projects));
          },
          onError: (Object e) {
            _error = e;
            _loading = false;
            notifyListeners();
          },
        );
  }

  /// [ProjectSortField.pageCount] has no dedicated SQL column to order by
  /// (`pageOrder` is stored as a JSON string), so it's applied here instead
  /// of in the repository query, the same hybrid SQL+in-memory approach the
  /// repository already uses for tag filtering.
  List<Project> _applySort(List<Project> projects) {
    if (_sortField != ProjectSortField.pageCount) return projects;
    final sorted = [...projects]
      ..sort((a, b) => a.pageOrder.length.compareTo(b.pageOrder.length));
    return _descending ? sorted.reversed.toList() : sorted;
  }

  /// Searches title, author, notes, and tags directly, plus any project with
  /// a matching recognized OCR block (SPEC 6.8: "Search by filename,
  /// metadata, tags, and OCR text"). The OCR match set is refreshed
  /// separately (it requires an async repository round trip) and re-applied
  /// here each time the project list itself changes.
  List<Project> _applySearch(List<Project> projects) {
    final text = _searchText.trim().toLowerCase();
    if (text.isEmpty) return projects;
    return projects.where((p) {
      if (p.title.toLowerCase().contains(text)) return true;
      if ((p.metadata.author ?? '').toLowerCase().contains(text)) {
        return true;
      }
      if ((p.metadata.notes ?? '').toLowerCase().contains(text)) return true;
      if (p.metadata.tags.any((tag) => tag.toLowerCase().contains(text))) {
        return true;
      }
      return _ocrMatchIds.contains(p.id);
    }).toList();
  }

  Future<void> _refreshOcrMatches() async {
    final searchId = ++_ocrSearchId;
    final text = _searchText.trim();
    final matches = text.isEmpty
        ? const <String>{}
        : await _projectRepository.projectIdsMatchingOcrText(text);
    if (searchId != _ocrSearchId) return;
    _ocrMatchIds = matches;
    _projects = _applySearch(_rawProjects);
    notifyListeners();
  }

  Future<void> _loadThumbnails(List<Project> projects) async {
    final pages = _pageRepository;
    if (pages == null) return;
    final loadId = ++_thumbnailLoadId;
    final next = <String, String>{};
    for (final project in projects) {
      if (project.pageOrder.isEmpty) continue;
      final page = await pages.getPage(project.pageOrder.first);
      if (page == null) continue;
      final path =
          page.processedImagePath ??
          page.thumbnailPath ??
          page.originalImagePath;
      if (path.isNotEmpty) next[project.id] = path;
    }
    if (loadId != _thumbnailLoadId) return;
    _thumbnails = next;
    notifyListeners();
  }

  void setSearchText(String value) {
    _searchText = value;
    _projects = _applySearch(_rawProjects);
    notifyListeners();
    unawaited(_refreshOcrMatches());
  }

  void setSortOrder(ProjectSortField field, {bool descending = true}) {
    _sortField = field;
    _descending = descending;
    _loading = true;
    notifyListeners();
    _subscribe();
  }

  void setFolderId(String? value) {
    _folderId = value;
    _loading = true;
    notifyListeners();
    _subscribe();
  }

  void setFavoritesOnly(bool value) {
    _favoritesOnly = value;
    if (value) _includeTrashed = false;
    _loading = true;
    notifyListeners();
    _subscribe();
  }

  void setIncludeTrashed(bool value) {
    _includeTrashed = value;
    if (value) _favoritesOnly = false;
    _loading = true;
    notifyListeners();
    _subscribe();
  }

  Future<void> toggleFavorite(Project project) => _projectRepository
      .updateProject(project.copyWith(isFavorite: !project.isFavorite));

  Future<void> moveToTrash(Project project) =>
      _projectRepository.moveToTrash(project.id);

  Future<void> restoreFromTrash(Project project) =>
      _projectRepository.restoreFromTrash(project.id);

  Future<void> deletePermanently(Project project) =>
      _projectRepository.deletePermanently(project.id);

  Future<void> renameProject(Project project, String title) =>
      _projectRepository.renameProject(project.id, title);

  Future<void> moveToFolder(Project project, String? folderId) =>
      _projectRepository.updateProject(
        project.copyWith(folderId: folderId, clearFolderId: folderId == null),
      );

  Future<void> updateTags(Project project, List<String> tags) =>
      _projectRepository.updateProject(
        project.copyWith(metadata: project.metadata.copyWith(tags: tags)),
      );

  @override
  void dispose() {
    _thumbnailLoadId++;
    _subscription?.cancel();
    super.dispose();
  }
}
