import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../../../domain/models/project.dart';
import '../../../../domain/models/scan_page.dart';
import '../../../../domain/repositories/page_path_allocator.dart';
import '../../../../domain/repositories/page_repository.dart';
import '../../../../domain/repositories/project_repository.dart';
import '../../../../domain/use_cases/process_book_spread_use_case.dart';
import '../../../core/widgets/page_image.dart';

/// Backs the manual book-spread split correction screen (SPEC 5.2
/// acceptance criterion: "the app creates two ordered pages and lets the
/// user correct the split").
class SpreadSplitViewModel extends ChangeNotifier {
  SpreadSplitViewModel({
    required this.pageId,
    required PageRepository pageRepository,
    required ProjectRepository projectRepository,
    required ProcessBookSpreadUseCase processBookSpreadUseCase,
    required PagePathAllocator paths,
  }) : _pageRepository = pageRepository,
       _projectRepository = projectRepository,
       _useCase = processBookSpreadUseCase,
       _paths = paths;

  final String pageId;
  final PageRepository _pageRepository;
  final ProjectRepository _projectRepository;
  final ProcessBookSpreadUseCase _useCase;
  final PagePathAllocator _paths;

  ScanPage? _physicalLeftPage;
  ScanPage? _physicalRightPage;

  String? _spreadImagePath;
  String? get spreadImagePath => _spreadImagePath;

  ui.Size? _imageSize;
  ui.Size? get imageSize => _imageSize;

  double _gutterX = 0.5;
  double get gutterX => _gutterX;

  bool _loading = true;
  bool get loading => _loading;

  bool _saving = false;
  bool get saving => _saving;

  Object? _error;
  Object? get error => _error;

  Future<void> initialize() async {
    try {
      final page = await _pageRepository.getPage(pageId);
      final siblingId = page?.spreadSiblingPageId;
      if (page == null || siblingId == null) {
        _error = StateError('Page is not part of a book spread');
        return;
      }
      final sibling = await _pageRepository.getPage(siblingId);
      if (sibling == null) {
        _error = StateError('Sibling page not found');
        return;
      }

      final project = await _projectRepository.getProject(page.projectId);
      final direction =
          project?.metadata.pageOrderDirection ??
          PageOrderDirection.leftToRight;

      // The physically-left half of the spread photo is the lower-sequence
      // page for left-to-right reading order, and the higher-sequence page
      // for right-to-left (SPEC 6.3 RTL support) — reading order and
      // physical left/right are inverted for RTL books.
      final pageIsPhysicallyLeft = direction == PageOrderDirection.rightToLeft
          ? page.sequence > sibling.sequence
          : page.sequence < sibling.sequence;
      _physicalLeftPage = pageIsPhysicallyLeft ? page : sibling;
      _physicalRightPage = pageIsPhysicallyLeft ? sibling : page;

      final spreadPath = ProcessBookSpreadUseCase.spreadOriginalPathFor(
        _paths,
        page.id,
        sibling.id,
      );
      if (!File(spreadPath).existsSync()) {
        _error = StateError('Original spread photo is no longer available');
        return;
      }
      _spreadImagePath = spreadPath;
      _imageSize = await _decodeImageSize(spreadPath);

      final leftWidth = (await _decodeImageSize(
        _physicalLeftPage!.originalImagePath,
      )).width;
      _gutterX = (leftWidth / _imageSize!.width).clamp(0.05, 0.95);
    } on Object catch (e) {
      _error = e;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Header-only: a full decode of a large scan here stalled the editor.
  Future<ui.Size> _decodeImageSize(String path) => readImageSize(path);

  void dragGutter(double normalizedDeltaX) {
    _gutterX = (_gutterX + normalizedDeltaX).clamp(0.05, 0.95);
    notifyListeners();
  }

  Future<bool> apply() async {
    final left = _physicalLeftPage;
    final right = _physicalRightPage;
    final spreadPath = _spreadImagePath;
    if (left == null || right == null || spreadPath == null) return false;
    _saving = true;
    notifyListeners();
    try {
      await _useCase.resplit(
        leftPage: left,
        rightPage: right,
        originalSpreadImagePath: spreadPath,
        gutterX: _gutterX,
      );
      return true;
    } on Object catch (e) {
      _error = e;
      return false;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }
}
