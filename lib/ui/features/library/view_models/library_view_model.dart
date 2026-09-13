import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../domain/models/project.dart';
import '../../../../domain/repositories/project_repository.dart';

class LibraryViewModel extends ChangeNotifier {
  LibraryViewModel({required ProjectRepository projectRepository})
    : _projectRepository = projectRepository {
    _subscribe();
  }

  final ProjectRepository _projectRepository;
  StreamSubscription<List<Project>>? _subscription;

  List<Project> _projects = const [];
  List<Project> get projects => _projects;

  bool _loading = true;
  bool get loading => _loading;

  String _searchText = '';
  String get searchText => _searchText;

  bool _favoritesOnly = false;
  bool get favoritesOnly => _favoritesOnly;

  Object? _error;
  Object? get error => _error;

  void _subscribe() {
    _subscription?.cancel();
    _subscription = _projectRepository
        .watchProjects(
          ProjectQuery(
            searchText: _searchText.isEmpty ? null : _searchText,
            favoritesOnly: _favoritesOnly,
          ),
        )
        .listen(
          (projects) {
            _projects = projects;
            _loading = false;
            _error = null;
            notifyListeners();
          },
          onError: (Object e) {
            _error = e;
            _loading = false;
            notifyListeners();
          },
        );
  }

  void setSearchText(String value) {
    _searchText = value;
    _loading = true;
    notifyListeners();
    _subscribe();
  }

  void setFavoritesOnly(bool value) {
    _favoritesOnly = value;
    _loading = true;
    notifyListeners();
    _subscribe();
  }

  Future<void> toggleFavorite(Project project) => _projectRepository
      .updateProject(project.copyWith(isFavorite: !project.isFavorite));

  Future<void> moveToTrash(Project project) =>
      _projectRepository.moveToTrash(project.id);

  Future<void> renameProject(Project project, String title) =>
      _projectRepository.renameProject(project.id, title);

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
