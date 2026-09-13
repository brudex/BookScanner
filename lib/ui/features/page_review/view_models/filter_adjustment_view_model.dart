import 'package:flutter/foundation.dart';

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

  bool _loading = true;
  bool get loading => _loading;

  bool _saving = false;
  bool get saving => _saving;

  Object? _error;
  Object? get error => _error;

  Future<void> initialize() async {
    try {
      final page = await _pageRepository.getPage(pageId);
      if (page == null) {
        _error = StateError('Page not found');
        _loading = false;
        notifyListeners();
        return;
      }
      _page = page;
      _filter = page.filter;
      _brightness = page.brightness;
      _contrast = page.contrast;
      _sharpness = page.sharpness;
    } on Exception catch (e) {
      _error = e;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void selectFilter(PageFilter filter) {
    _filter = filter;
    notifyListeners();
  }

  void setBrightness(double value) {
    _brightness = value;
    notifyListeners();
  }

  void setContrast(double value) {
    _contrast = value;
    notifyListeners();
  }

  void setSharpness(double value) {
    _sharpness = value;
    notifyListeners();
  }

  Future<bool> apply() async {
    final page = _page;
    if (page == null) return false;
    _saving = true;
    notifyListeners();
    try {
      await _capturePageUseCase.reprocessPage(
        page,
        filter: _filter,
        brightness: _brightness,
        contrast: _contrast,
        sharpness: _sharpness,
      );
      return true;
    } on Exception catch (e) {
      _error = e;
      return false;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }
}
