import 'package:flutter/foundation.dart';

import '../../../../domain/models/scan_page.dart';
import '../../../../domain/repositories/page_repository.dart';
import '../../../../domain/repositories/project_repository.dart';
import '../../../../domain/use_cases/capture_page_use_case.dart';
import 'filter_adjustment_view_model.dart';

/// Walks every page captured in a session one-by-one for filter/crop polish
/// (TapScanner-style post-scan edit). Naming the project happens after the
/// last page is saved — not mid-capture.
class PostCaptureEditViewModel extends ChangeNotifier {
  PostCaptureEditViewModel({
    required this.projectId,
    required PageRepository pageRepository,
    required ProjectRepository projectRepository,
    required CapturePageUseCase capturePageUseCase,
  }) : _pageRepository = pageRepository,
       _projectRepository = projectRepository,
       _capturePageUseCase = capturePageUseCase;

  final String projectId;
  final PageRepository _pageRepository;
  final ProjectRepository _projectRepository;
  final CapturePageUseCase _capturePageUseCase;

  List<ScanPage> _pages = const [];
  List<ScanPage> get pages => _pages;

  int _index = 0;
  int get index => _index;

  FilterAdjustmentViewModel? _editor;
  FilterAdjustmentViewModel? get editor => _editor;

  bool _loading = true;
  bool get loading => _loading;

  bool _finished = false;
  bool get finished => _finished;

  Object? _error;
  Object? get error => _error;

  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  ScanPage? get currentPage =>
      _pages.isEmpty ? null : _pages[_index.clamp(0, _pages.length - 1)];

  bool get isLastPage => _pages.isEmpty || _index >= _pages.length - 1;

  Future<void> initialize({String? initialPageId}) async {
    _loading = true;
    _notify();
    try {
      final project = await _projectRepository.getProject(projectId);
      final all = await _pageRepository.getPages(projectId);
      final byId = {for (final p in all) p.id: p};
      if (project != null && project.pageOrder.isNotEmpty) {
        _pages = [
          for (final id in project.pageOrder)
            if (byId[id] != null) byId[id]!,
        ];
      } else {
        _pages = [...all]..sort((a, b) => a.sequence.compareTo(b.sequence));
      }
      if (_pages.isEmpty) {
        _finished = true;
      } else {
        if (initialPageId != null) {
          final idx = _pages.indexWhere((p) => p.id == initialPageId);
          if (idx >= 0) _index = idx;
        }
        await _bindEditor();
      }
    } on Exception catch (e) {
      _error = e;
    } finally {
      _loading = false;
      _notify();
    }
  }

  Future<void> _bindEditor() async {
    final previous = _editor;
    if (previous != null) {
      // Drop the listener while the editor is still alive, then dispose it.
      _editor = null;
      _notify();
      previous.dispose();
    }
    final page = currentPage;
    if (page == null || _disposed) return;
    final editor = FilterAdjustmentViewModel(
      pageId: page.id,
      pageRepository: _pageRepository,
      capturePageUseCase: _capturePageUseCase,
    );
    await editor.initialize();
    if (_disposed) {
      editor.dispose();
      return;
    }
    _editor = editor;
  }

  /// After crop (or any external page mutation), refresh the in-memory page
  /// list and re-show the current editor from disk.
  Future<void> reloadCurrentAfterExternalEdit() async {
    final currentId = currentPage?.id;
    final all = await _pageRepository.getPages(projectId);
    final byId = {for (final p in all) p.id: p};
    final project = await _projectRepository.getProject(projectId);
    if (project != null && project.pageOrder.isNotEmpty) {
      _pages = [
        for (final id in project.pageOrder)
          if (byId[id] != null) byId[id]!,
      ];
    } else {
      _pages = [...all]..sort((a, b) => a.sequence.compareTo(b.sequence));
    }
    if (currentId != null) {
      final idx = _pages.indexWhere((p) => p.id == currentId);
      if (idx >= 0) _index = idx;
    }
    final editor = _editor;
    if (editor != null && editor.pageId == currentPage?.id) {
      await editor.reloadFromRepository();
    } else {
      await _bindEditor();
    }
    _notify();
  }

  Future<bool> saveAndAdvance() async {
    final editor = _editor;
    if (editor == null) return false;
    final ok = await editor.apply();
    if (!ok) {
      _error = editor.error;
      _notify();
      return false;
    }
    if (_disposed) return false;
    if (isLastPage) {
      _finished = true;
      _notify();
      return true;
    }
    _index++;
    await _bindEditor();
    _notify();
    return true;
  }

  Future<void> renameProject(String title) =>
      _projectRepository.renameProject(projectId, title);

  @override
  void dispose() {
    _disposed = true;
    _editor?.dispose();
    _editor = null;
    super.dispose();
  }
}
