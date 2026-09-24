import 'dart:async';

import 'package:bookscanner/domain/models/project.dart';
import 'package:bookscanner/domain/repositories/project_repository.dart';

/// In-memory test double — a real, deterministic implementation (not a
/// mock), matching the project's "fakes over mocks" testing convention.
class FakeProjectRepository implements ProjectRepository {
  final _projects = <String, Project>{};
  final _controller = StreamController<List<Project>>.broadcast();

  void seed(List<Project> projects) {
    for (final p in projects) {
      _projects[p.id] = p;
    }
    _emit();
  }

  void _emit() => _controller.add(_projects.values.toList());

  @override
  Stream<List<Project>> watchProjects(ProjectQuery query) async* {
    yield _filtered(query);
    await for (final _ in _controller.stream) {
      yield _filtered(query);
    }
  }

  List<Project> _filtered(ProjectQuery query) {
    var list = _projects.values.where(
      (p) =>
          p.isTrashed == query.includeTrashed ||
          !query.includeTrashed && !p.isTrashed,
    );
    if (query.searchText != null && query.searchText!.isNotEmpty) {
      list = list.where(
        (p) => p.title.toLowerCase().contains(query.searchText!.toLowerCase()),
      );
    }
    if (query.favoritesOnly) {
      list = list.where((p) => p.isFavorite);
    }
    return list.toList();
  }

  @override
  Stream<Project?> watchProject(String id) async* {
    yield _projects[id];
  }

  @override
  Future<Project?> getProject(String id) async => _projects[id];

  @override
  Future<Set<String>> projectIdsMatchingOcrText(String text) async => {};

  @override
  Future<Project> createProject({
    required ProjectType type,
    required String title,
  }) async {
    final now = DateTime.now();
    final project = Project(
      id: 'p${_projects.length + 1}',
      type: type,
      title: title,
      metadata: const ProjectMetadata(),
      pageOrder: const [],
      createdAt: now,
      updatedAt: now,
      processingState: ProcessingState.idle,
    );
    _projects[project.id] = project;
    _emit();
    return project;
  }

  @override
  Future<void> updateProject(Project project) async {
    _projects[project.id] = project;
    _emit();
  }

  @override
  Future<void> moveToTrash(String id) async {
    final p = _projects[id];
    if (p == null) return;
    _projects[id] = p.copyWith(isTrashed: true);
    _emit();
  }

  @override
  Future<void> restoreFromTrash(String id) async {
    final p = _projects[id];
    if (p == null) return;
    _projects[id] = p.copyWith(isTrashed: false);
    _emit();
  }

  @override
  Future<void> deletePermanently(String id) async {
    _projects.remove(id);
    _emit();
  }

  @override
  Future<void> renameProject(String id, String title) async {
    final p = _projects[id];
    if (p == null) return;
    _projects[id] = p.copyWith(title: title);
    _emit();
  }
}
