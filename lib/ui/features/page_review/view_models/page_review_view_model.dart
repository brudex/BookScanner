import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../domain/models/geometry.dart';
import '../../../../domain/models/project.dart';
import '../../../../domain/models/scan_page.dart';
import '../../../../domain/repositories/page_repository.dart';
import '../../../../domain/repositories/project_repository.dart';
import '../../../../domain/use_cases/capture_page_use_case.dart';
import '../../../../domain/use_cases/detect_page_anomalies_use_case.dart';

class PageReviewViewModel extends ChangeNotifier {
  PageReviewViewModel({
    required this.projectId,
    required PageRepository pageRepository,
    required DetectPageAnomaliesUseCase detectAnomaliesUseCase,
    required CapturePageUseCase capturePageUseCase,
    ProjectRepository? projectRepository,
  }) : _pageRepository = pageRepository,
       _detectAnomaliesUseCase = detectAnomaliesUseCase,
       _capturePageUseCase = capturePageUseCase {
    _subscribe();
    if (projectRepository != null) unawaited(_loadProject(projectRepository));
  }

  Project? _project;

  /// The project, once loaded; null when no [ProjectRepository] was given.
  /// Book projects offer "Split into two pages" on unsplit pages.
  Project? get project => _project;

  bool _disposed = false;

  Future<void> _loadProject(ProjectRepository repository) async {
    final project = await repository.getProject(projectId);
    if (_disposed) return;
    _project = project;
    notifyListeners();
  }

  final String projectId;
  final PageRepository _pageRepository;
  final DetectPageAnomaliesUseCase _detectAnomaliesUseCase;
  final CapturePageUseCase _capturePageUseCase;
  StreamSubscription<List<ScanPage>>? _subscription;

  final Set<String> selectedIds = {};

  void toggleSelected(String pageId) {
    if (!selectedIds.remove(pageId)) selectedIds.add(pageId);
    notifyListeners();
  }

  void clearSelection() {
    selectedIds.clear();
    notifyListeners();
  }

  List<ScanPage> _pages = const [];
  List<ScanPage> get pages => _pages;

  bool _loading = true;
  bool get loading => _loading;

  /// Session-only display preference (not persisted -- a UI display mode,
  /// not project data). Grid view is browse-only: `ReorderableListView` has
  /// no first-party grid equivalent in this Flutter version, so drag-reorder
  /// stays List-view-only; the popup menu (rotate/duplicate/delete/etc.)
  /// still works from either view.
  bool _gridView = false;
  bool get gridView => _gridView;

  void toggleGridView() {
    _gridView = !_gridView;
    notifyListeners();
  }

  void _subscribe() {
    _subscription = _pageRepository.watchPages(projectId).listen((pages) {
      _pages = pages;
      _loading = false;
      notifyListeners();
      unawaited(_refreshAnomalies());
    });
  }

  Future<void> _refreshAnomalies() async {
    final result = await _detectAnomaliesUseCase.analyze(projectId);
    if (result.duplicatesOf.isEmpty &&
        result.likelyMissingBeforeSequence.isEmpty) {
      return;
    }
    for (final page in _pages) {
      final dupOf = result.duplicatesOf[page.id];
      final missing = result.likelyMissingBeforeSequence.contains(
        page.sequence,
      );
      if (dupOf != page.duplicateOfPageId ||
          missing != page.likelyMissingBefore) {
        await _pageRepository.updatePage(
          page.copyWith(duplicateOfPageId: dupOf, likelyMissingBefore: missing),
        );
      }
    }
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    final updated = [..._pages];
    if (newIndex > oldIndex) newIndex -= 1;
    final moved = updated.removeAt(oldIndex);
    updated.insert(newIndex, moved);
    _pages = updated;
    notifyListeners();
    await _pageRepository.reorderPages(
      projectId,
      updated.map((p) => p.id).toList(),
    );
  }

  Future<void> rotate(ScanPage page) => _pageRepository.updatePage(
    page.copyWith(rotationDegrees: (page.rotationDegrees + 90) % 360),
  );

  Future<void> duplicate(ScanPage page) =>
      _pageRepository.duplicatePage(page.id);

  Future<void> delete(ScanPage page) => _pageRepository.deletePage(page.id);

  /// Sets or clears the user-facing page label (cover, Roman numeral, etc.).
  Future<void> setLogicalPageLabel(ScanPage page, String? label) {
    final trimmed = label?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return _pageRepository.updatePage(
        page.copyWith(clearLogicalPageLabel: true),
      );
    }
    return _pageRepository.updatePage(page.copyWith(logicalPageLabel: trimmed));
  }

  /// Resets filter/adjustments/crop/rotation and re-derives the processed
  /// image from the retained [ScanPage.originalImagePath] (SPEC 6.2).
  Future<void> revertToOriginal(ScanPage page) =>
      _capturePageUseCase.reprocessPage(
        page,
        cropPoints: Quad.fullFrame,
        rotationDegrees: 0,
        fineRotationDegrees: 0,
        filter: PageFilter.original,
        brightness: 0,
        contrast: 0,
        sharpness: 0,
        threshold: 0.5,
      );

  Future<void> rotateSelected() async {
    for (final page in _pages.where((p) => selectedIds.contains(p.id))) {
      await rotate(page);
    }
    clearSelection();
  }

  Future<void> duplicateSelected() async {
    for (final page in _pages.where((p) => selectedIds.contains(p.id))) {
      await duplicate(page);
    }
    clearSelection();
  }

  Future<void> deleteSelected() async {
    for (final page in _pages.where((p) => selectedIds.contains(p.id))) {
      await delete(page);
    }
    clearSelection();
  }

  Future<void> dismissWarning(ScanPage page, String warningName) =>
      _pageRepository.updatePage(
        page.copyWith(
          dismissedWarnings: {...page.dismissedWarnings, warningName},
        ),
      );

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    super.dispose();
  }
}
