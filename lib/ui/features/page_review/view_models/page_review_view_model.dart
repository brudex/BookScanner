import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../domain/models/scan_page.dart';
import '../../../../domain/repositories/page_repository.dart';
import '../../../../domain/use_cases/detect_page_anomalies_use_case.dart';

class PageReviewViewModel extends ChangeNotifier {
  PageReviewViewModel({
    required this.projectId,
    required PageRepository pageRepository,
    required DetectPageAnomaliesUseCase detectAnomaliesUseCase,
  }) : _pageRepository = pageRepository,
       _detectAnomaliesUseCase = detectAnomaliesUseCase {
    _subscribe();
  }

  final String projectId;
  final PageRepository _pageRepository;
  final DetectPageAnomaliesUseCase _detectAnomaliesUseCase;
  StreamSubscription<List<ScanPage>>? _subscription;

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

  Future<void> dismissWarning(ScanPage page, String warningName) =>
      _pageRepository.updatePage(
        page.copyWith(
          dismissedWarnings: {...page.dismissedWarnings, warningName},
        ),
      );

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
