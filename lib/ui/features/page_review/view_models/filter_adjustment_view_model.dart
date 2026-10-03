import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../../../domain/models/scan_page.dart';
import '../../../../domain/repositories/page_repository.dart';
import '../../../../domain/use_cases/capture_page_use_case.dart';

/// Backs the filter/brightness/contrast/sharpness adjustment screen (SPEC
/// 6.2: filters and brightness/contrast/sharpness adjustment). Mirrors
/// [CropCorrectionViewModel]'s shape exactly: load the page, mutate
/// transient local state as the user adjusts controls, and only persist +
/// re-run the real enhancement pipeline when [apply] is called.
class FilterAdjustmentViewModel extends ChangeNotifier {
  FilterAdjustmentViewModel({
    required this.pageId,
    required PageRepository pageRepository,
    required CapturePageUseCase capturePageUseCase,
  }) : _pageRepository = pageRepository,
       _capturePageUseCase = capturePageUseCase;

  final String pageId;
  final PageRepository _pageRepository;
  final CapturePageUseCase _capturePageUseCase;

  ScanPage? _page;
  ScanPage? get page => _page;

  PageFilter _filter = PageFilter.original;
  PageFilter get filter => _filter;

  double _brightness = 0;
  double get brightness => _brightness;

  double _contrast = 0;
  double get contrast => _contrast;

  double _sharpness = 0;
  double get sharpness => _sharpness;

  double _fineRotationDegrees = 0;
  double get fineRotationDegrees => _fineRotationDegrees;

  double _threshold = 0.5;
  double get threshold => _threshold;

  bool _loading = true;
  bool get loading => _loading;

  bool _saving = false;
  bool get saving => _saving;

  bool _previewRendering = false;
  bool get previewRendering => _previewRendering;

  Object? _error;
  Object? get error => _error;

  /// Bumped whenever a preview JPEG is rewritten so [Image.file] keys change.
  int _previewEpoch = 0;
  int get previewEpoch => _previewEpoch;

  String? _livePreviewPath;
  Timer? _previewDebounce;
  int _previewToken = 0;
  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// True when controls match the last saved page — show that processed JPEG.
  bool get showingSavedProcessed {
    final page = _page;
    if (page == null) return false;
    final processed = page.processedImagePath;
    if (processed == null || processed.isEmpty) return false;
    return _filter == page.filter &&
        _brightness == page.brightness &&
        _contrast == page.contrast &&
        _sharpness == page.sharpness &&
        _threshold == page.threshold &&
        _fineRotationDegrees == page.fineRotationDegrees;
  }

  /// True when a real crop+filter preview JPEG is ready (not a ColorFilter
  /// approximation on the full original).
  bool get showingRenderedPreview =>
      showingSavedProcessed ||
      (_livePreviewPath != null && !showingSavedProcessed);

  /// Prefer: saved processed → live rendered preview (cropped+filtered) →
  /// last processed (keeps crop framing) → original as last resort.
  String? get previewImagePath {
    final page = _page;
    if (page == null) return null;
    if (showingSavedProcessed) return page.processedImagePath;
    if (_livePreviewPath != null) return _livePreviewPath;
    return page.processedImagePath ?? page.originalImagePath;
  }

  Future<void> initialize() async {
    try {
      final page = await _pageRepository.getPage(pageId);
      if (page == null) {
        _error = StateError('Page not found');
        _loading = false;
        _notify();
        return;
      }
      if (_disposed) return;
      _adoptPage(page);
    } on Object catch (e) {
      _error = e;
    } finally {
      _loading = false;
      _notify();
    }
  }

  /// Re-reads the page from the repository (e.g. after crop correction) and
  /// resets controls to the newly saved look.
  Future<void> reloadFromRepository() async {
    final page = await _pageRepository.getPage(pageId);
    if (page == null) return;
    final path = page.processedImagePath;
    if (path != null) {
      await _evictProcessedPreview(path);
    }
    if (_disposed) return;
    _livePreviewPath = null;
    _adoptPage(page);
    _previewEpoch++;
    _notify();
  }

  void _adoptPage(ScanPage page) {
    _page = page;
    _filter = page.filter;
    _brightness = page.brightness;
    _contrast = page.contrast;
    _sharpness = page.sharpness;
    _fineRotationDegrees = page.fineRotationDegrees;
    _threshold = page.threshold;
    _error = null;
  }

  Future<void> _evictProcessedPreview(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      await FileImage(File(path)).evict();
    } on Object {
      // PaintingBinding not available outside widget tests / the app.
    }
  }

  void selectFilter(PageFilter filter) {
    _filter = filter;
    _scheduleLivePreview();
    _notify();
  }

  void setBrightness(double value) {
    _brightness = value;
    _scheduleLivePreview();
    _notify();
  }

  void setContrast(double value) {
    _contrast = value;
    _scheduleLivePreview();
    _notify();
  }

  void setSharpness(double value) {
    _sharpness = value;
    _scheduleLivePreview();
    _notify();
  }

  void setFineRotationDegrees(double value) {
    _fineRotationDegrees = value;
    _scheduleLivePreview();
    _notify();
  }

  void setThreshold(double value) {
    _threshold = value;
    _scheduleLivePreview();
    _notify();
  }

  void _scheduleLivePreview() {
    _previewDebounce?.cancel();
    if (showingSavedProcessed) {
      _livePreviewPath = null;
      _previewRendering = false;
      return;
    }
    // Show progress from the tap itself, not only once the debounced
    // render starts, so the user sees the change is being applied.
    _previewRendering = true;
    _previewDebounce = Timer(const Duration(milliseconds: 180), () {
      unawaited(_renderLivePreview());
    });
  }

  /// A full-resolution preview render is in progress. At most one runs at
  /// a time: dragging a slider used to start a new render on every pause
  /// without stopping older ones, and several concurrent renders of one
  /// page exhausted memory and froze the app (ANR, then killed).
  bool _renderInFlight = false;

  /// Controls changed while a render was in flight; render once more with
  /// the latest values when it finishes.
  bool _renderAgain = false;

  Future<void> _renderLivePreview() async {
    if (_renderInFlight) {
      _renderAgain = true;
      return;
    }
    final page = _page;
    if (page == null || showingSavedProcessed) {
      _previewRendering = false;
      _notify();
      return;
    }
    _renderInFlight = true;
    _renderAgain = false;
    final token = ++_previewToken;
    _previewRendering = true;
    _notify();
    try {
      final path = await _capturePageUseCase.renderAdjustedPreview(
        page,
        filter: _filter,
        brightness: _brightness,
        contrast: _contrast,
        sharpness: _sharpness,
        fineRotationDegrees: _fineRotationDegrees,
        threshold: _threshold,
      );
      if (_disposed || token != _previewToken) return;
      await _evictProcessedPreview(path);
      if (_disposed || token != _previewToken) return;
      _livePreviewPath = path;
      _previewEpoch++;
    } on Object catch (e) {
      if (_disposed || token != _previewToken) return;
      _error = e;
    } finally {
      _renderInFlight = false;
      if (!_disposed && token == _previewToken) {
        _previewRendering = false;
        _notify();
      }
      if (_renderAgain && !_disposed) {
        _renderAgain = false;
        if (!showingSavedProcessed) unawaited(_renderLivePreview());
      }
    }
  }

  Future<bool> apply() async {
    final page = _page;
    if (page == null) return false;
    _previewDebounce?.cancel();
    _previewToken++;
    _saving = true;
    _notify();
    try {
      final updated = await _capturePageUseCase.reprocessPage(
        page,
        filter: _filter,
        brightness: _brightness,
        contrast: _contrast,
        sharpness: _sharpness,
        fineRotationDegrees: _fineRotationDegrees,
        threshold: _threshold,
      );
      if (_disposed) return false;
      final path = updated.processedImagePath;
      if (path != null) {
        await _evictProcessedPreview(path);
      }
      if (_disposed) return false;
      _livePreviewPath = null;
      _page = updated;
      _previewEpoch++;
      return true;
    } on Object catch (e) {
      _error = e;
      return false;
    } finally {
      _saving = false;
      // Save cancels the live preview; never leave the controls locked.
      _previewRendering = false;
      _notify();
    }
  }

  /// Cancels an in-flight live-preview debounce (call from the screen's
  /// dispose even when the view model itself is owned by a test).
  void cancelPendingPreview() {
    _previewDebounce?.cancel();
    _previewDebounce = null;
    _previewToken++;
    _previewRendering = false;
    _renderAgain = false;
  }

  @override
  void dispose() {
    _disposed = true;
    cancelPendingPreview();
    super.dispose();
  }
}
