import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../../domain/models/export_job.dart';
import '../../../../domain/models/page_source.dart';
import '../../../../domain/providers/document_export_provider.dart';
import '../../../../domain/providers/pdf_rasterizer_provider.dart';
import '../../../../domain/repositories/working_session_path_allocator.dart';
import '../../../../domain/use_cases/export_page_inputs_use_case.dart';
import '../../../../domain/use_cases/load_page_source_use_case.dart';
import '../../../../domain/use_cases/load_project_page_inputs_use_case.dart';

/// Drives the multi-source page-composition screen (SPEC 6.5 "editing":
/// merge/insert/replace/extract/split/duplicate/rotate/reorder/delete pages
/// across projects and imported PDFs/images). Unlike [PageReviewViewModel],
/// this holds a purely in-memory, ephemeral working list rather than
/// persisting through [PageRepository] — the composed document only becomes
/// a real artifact once exported, matching the transient-working-state
/// pattern already used by `CropCorrectionViewModel`/`SpreadSplitViewModel`.
class PageOperationsViewModel extends ChangeNotifier {
  PageOperationsViewModel({
    required this.hostProjectId,
    required LoadProjectPageInputsUseCase projectPageLoader,
    required LoadPageSourceUseCase pageSourceLoader,
    required ExportPageInputsUseCase exportUseCase,
    required WorkingSessionPathAllocator workingPaths,
    required PdfRasterizerProvider rasterizer,
    Uuid? uuid,
  }) : _projectPageLoader = projectPageLoader,
       _pageSourceLoader = pageSourceLoader,
       _exportUseCase = exportUseCase,
       _workingPaths = workingPaths,
       _rasterizer = rasterizer,
       _uuid = uuid ?? const Uuid(),
       _sessionId = (uuid ?? const Uuid()).v4();

  final String hostProjectId;
  final LoadProjectPageInputsUseCase _projectPageLoader;
  final LoadPageSourceUseCase _pageSourceLoader;
  final ExportPageInputsUseCase _exportUseCase;
  final WorkingSessionPathAllocator _workingPaths;
  final PdfRasterizerProvider _rasterizer;
  final Uuid _uuid;
  final String _sessionId;

  List<ExportPageInput> _pages = const [];
  List<ExportPageInput> get pages => List.unmodifiable(_pages);

  bool _loading = true;
  bool get loading => _loading;

  /// pageId -> "insert a split boundary immediately after this page". Keyed
  /// by pageId, not index, so a reorder/insert/delete never desyncs markers.
  final Set<String> _splitAfterPageIds = {};
  Set<String> get splitAfterPageIds => Set.unmodifiable(_splitAfterPageIds);

  final Set<String> _selectedForExtract = {};
  Set<String> get selectedForExtract => Set.unmodifiable(_selectedForExtract);

  bool get anyPageMissingOcr => _pages.any((p) => p.ocrBlocks.isEmpty);

  double? _progress;
  double? get progress => _progress;

  ExportJob? _job;
  ExportJob? get job => _job;

  List<ExportJob>? _splitJobs;
  List<ExportJob>? get splitJobs => _splitJobs;

  int _jobsCompleted = 0;
  int get jobsCompleted => _jobsCompleted;
  int _jobsTotal = 0;
  int get jobsTotal => _jobsTotal;

  Object? _error;
  Object? get error => _error;

  Future<void> initialize() async {
    _pages = await _projectPageLoader(hostProjectId);
    _loading = false;
    notifyListeners();
  }

  void reorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    final updated = [..._pages];
    final moved = updated.removeAt(oldIndex);
    updated.insert(newIndex, moved);
    _pages = updated;
    notifyListeners();
  }

  void rotate(String pageId) {
    _pages = [
      for (final page in _pages)
        if (page.pageId == pageId)
          page.copyWith(rotationDegrees: (page.rotationDegrees + 90) % 360)
        else
          page,
    ];
    notifyListeners();
  }

  void duplicate(String pageId) {
    final index = _pages.indexWhere((p) => p.pageId == pageId);
    if (index == -1) return;
    final copy = _pages[index].copyWith(pageId: _uuid.v4());
    _pages = [..._pages]..insert(index + 1, copy);
    notifyListeners();
  }

  void delete(String pageId) {
    _pages = _pages.where((p) => p.pageId != pageId).toList();
    _splitAfterPageIds.remove(pageId);
    _selectedForExtract.remove(pageId);
    notifyListeners();
  }

  Future<void> insertBefore(String beforePageId, PageSource source) async {
    final newPages = await _pageSourceLoader(source, sessionId: _sessionId);
    final index = _pages.indexWhere((p) => p.pageId == beforePageId);
    if (index == -1) return;
    _pages = [..._pages]..insertAll(index, newPages);
    notifyListeners();
  }

  Future<void> replace(String pageId, PageSource source) async {
    final newPages = await _pageSourceLoader(source, sessionId: _sessionId);
    final index = _pages.indexWhere((p) => p.pageId == pageId);
    if (index == -1) return;
    _pages = [..._pages]
      ..removeAt(index)
      ..insertAll(index, newPages);
    _splitAfterPageIds.remove(pageId);
    _selectedForExtract.remove(pageId);
    notifyListeners();
  }

  Future<void> mergeAppend(PageSource source) async {
    final newPages = await _pageSourceLoader(source, sessionId: _sessionId);
    _pages = [..._pages, ...newPages];
    notifyListeners();
  }

  void toggleSplitAfter(String pageId) {
    if (!_splitAfterPageIds.remove(pageId)) _splitAfterPageIds.add(pageId);
    notifyListeners();
  }

  void toggleSelectedForExtract(String pageId) {
    if (!_selectedForExtract.remove(pageId)) _selectedForExtract.add(pageId);
    notifyListeners();
  }

  /// Low-dpi rasterization for a "pick pages to import" thumbnail grid --
  /// separate from the dpi:150 pass [LoadPageSourceUseCase] uses to actually
  /// import pages, which would be needlessly slow/large for a preview.
  Future<List<RasterizedPdfPage>> loadPdfThumbnails(String pdfPath) =>
      _rasterizer.rasterize(pdfPath, dpi: 60).toList();

  /// Returns to the composer from a failed export result so the user can
  /// adjust the working list and try again -- deliberately not an automatic
  /// "retry the exact same call" like `ExportViewModel`'s retry, since this
  /// screen has three different export actions (whole/extract/split) and
  /// there's no single obvious one to blindly repeat.
  void resetExportState() {
    _job = null;
    _splitJobs = null;
    _error = null;
    _progress = null;
    notifyListeners();
  }

  Future<void> exportWhole({
    required String title,
    PdfExportOptions options = const PdfExportOptions(),
  }) =>
      _runSingleExport(pages: List.of(_pages), title: title, options: options);

  Future<void> extractSelected({
    required String title,
    PdfExportOptions options = const PdfExportOptions(),
  }) => _runSingleExport(
    pages: [
      for (final page in _pages)
        if (_selectedForExtract.contains(page.pageId)) page,
    ],
    title: title,
    options: options,
  );

  Future<void> _runSingleExport({
    required List<ExportPageInput> pages,
    required String title,
    required PdfExportOptions options,
  }) async {
    _job = null;
    _splitJobs = null;
    _error = null;
    _progress = 0;
    notifyListeners();
    try {
      _job = await _exportUseCase.exportPdf(
        hostProjectId: hostProjectId,
        title: title,
        pages: pages,
        options: options,
        onProgress: (p) {
          _progress = p;
          notifyListeners();
        },
      );
    } on Exception catch (e) {
      _error = e;
    }
    notifyListeners();
  }

  Future<void> exportSplit({
    required String titlePrefix,
    PdfExportOptions options = const PdfExportOptions(),
  }) async {
    final groups = _groupsFromMarkers();
    _job = null;
    _splitJobs = null;
    _error = null;
    _jobsCompleted = 0;
    _jobsTotal = groups.length;
    notifyListeners();
    try {
      _splitJobs = await _exportUseCase.splitPdf(
        hostProjectId: hostProjectId,
        titlePrefix: titlePrefix,
        groups: groups,
        options: options,
        onJobProgress: (completed, total) {
          _jobsCompleted = completed;
          _jobsTotal = total;
          notifyListeners();
        },
      );
    } on Exception catch (e) {
      _error = e;
    }
    notifyListeners();
  }

  List<List<ExportPageInput>> _groupsFromMarkers() {
    final groups = <List<ExportPageInput>>[];
    var current = <ExportPageInput>[];
    for (final page in _pages) {
      current.add(page);
      if (_splitAfterPageIds.contains(page.pageId)) {
        groups.add(current);
        current = [];
      }
    }
    if (current.isNotEmpty) groups.add(current);
    return groups;
  }

  @override
  void dispose() {
    unawaited(_workingPaths.clearSession(_sessionId));
    super.dispose();
  }
}
