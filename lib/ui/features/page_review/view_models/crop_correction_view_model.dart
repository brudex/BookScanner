import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../../../domain/models/geometry.dart';
import '../../../../domain/models/scan_page.dart';
import '../../../../domain/providers/page_detection_provider.dart';
import '../../../../domain/repositories/page_repository.dart';
import '../../../../domain/use_cases/capture_page_use_case.dart';

enum CropCorner { topLeft, topRight, bottomRight, bottomLeft }

/// Backs the manual four-corner crop correction screen (SPEC 6.2: "Manual
/// four-corner crop and fine rotation"; SPEC 12 acceptance criterion:
/// "Given a rectangular document photographed at an angle, the saved page
/// is cropped and perspective-corrected, and the user can manually adjust
/// all four corners").
class CropCorrectionViewModel extends ChangeNotifier {
  CropCorrectionViewModel({
    required this.pageId,
    required PageRepository pageRepository,
    required CapturePageUseCase capturePageUseCase,
    required PageDetectionProvider detectionProvider,
  }) : _pageRepository = pageRepository,
       _capturePageUseCase = capturePageUseCase,
       _detectionProvider = detectionProvider;

  final String pageId;
  final PageRepository _pageRepository;
  final CapturePageUseCase _capturePageUseCase;
  final PageDetectionProvider _detectionProvider;

  ScanPage? _page;
  ScanPage? get page => _page;

  Quad _quad = Quad.fullFrame;
  Quad get quad => _quad;

  /// Intrinsic pixel size of the original image, needed to map normalized
  /// corner coordinates onto the fitted display rectangle precisely.
  ui.Size? _imageSize;
  ui.Size? get imageSize => _imageSize;

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
      _quad = page.cropPoints ?? Quad.fullFrame;
      _imageSize = await _decodeImageSize(page.originalImagePath);
    } on Exception catch (e) {
      _error = e;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<ui.Size> _decodeImageSize(String path) async {
    final bytes = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final size = ui.Size(
      frame.image.width.toDouble(),
      frame.image.height.toDouble(),
    );
    frame.image.dispose();
    return size;
  }

  Point2D _cornerOf(CropCorner corner) => switch (corner) {
    CropCorner.topLeft => _quad.topLeft,
    CropCorner.topRight => _quad.topRight,
    CropCorner.bottomRight => _quad.bottomRight,
    CropCorner.bottomLeft => _quad.bottomLeft,
  };

  /// Moves [corner] by a normalized (0..1-space) delta, clamped so it never
  /// leaves the image bounds.
  void dragCorner(CropCorner corner, ui.Offset normalizedDelta) {
    final current = _cornerOf(corner);
    final next = Point2D(
      x: (current.x + normalizedDelta.dx).clamp(0.0, 1.0),
      y: (current.y + normalizedDelta.dy).clamp(0.0, 1.0),
    );
    _quad = switch (corner) {
      CropCorner.topLeft => _quad.copyWith(topLeft: next),
      CropCorner.topRight => _quad.copyWith(topRight: next),
      CropCorner.bottomRight => _quad.copyWith(bottomRight: next),
      CropCorner.bottomLeft => _quad.copyWith(bottomLeft: next),
    };
    notifyListeners();
  }

  void resetToFullFrame() {
    _quad = Quad.fullFrame;
    notifyListeners();
  }

  Future<void> resetToDetected() async {
    final page = _page;
    if (page == null) return;
    final detected = await _detectionProvider.detectQuad(
      page.originalImagePath,
    );
    _quad = detected ?? Quad.fullFrame;
    notifyListeners();
  }

  Future<bool> apply() async {
    final page = _page;
    if (page == null) return false;
    _saving = true;
    notifyListeners();
    try {
      await _capturePageUseCase.reprocessPage(page, cropPoints: _quad);
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
