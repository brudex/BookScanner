import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../../../domain/models/geometry.dart';
import '../../../../domain/models/scan_page.dart';
import '../../../../domain/providers/page_detection_provider.dart';
import '../../../../domain/repositories/page_repository.dart';
import '../../../../domain/use_cases/capture_page_use_case.dart';
import '../../../core/widgets/page_image.dart';

/// Draggable crop controls matching Tap Scanner's `SimpleCropImageView`:
/// 4 corners + 4 edge midpoints. Edge handles still edit the same stored
/// 4-point [Quad] (perspective warp stays 4-point).
enum CropHandle {
  topLeft,
  topRight,
  bottomRight,
  bottomLeft,
  top,
  right,
  bottom,
  left,
}

/// Legacy alias used by older tests / call sites.
typedef CropCorner = CropHandle;

/// Backs the manual crop correction screen (SPEC 6.2 / Tap Scanner parity).
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

  ui.Size? _imageSize;
  ui.Size? get imageSize => _imageSize;

  bool _loading = true;
  bool get loading => _loading;

  bool _saving = false;
  bool get saving => _saving;

  Object? _error;
  Object? get error => _error;

  /// Minimum normalized edge length — mirrors Tap Scanner's `z1` min frame.
  static const double minEdge = 0.04;

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
    } on Object catch (e) {
      _error = e;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Header-only: a full decode of a large scan here stalled the editor.
  Future<ui.Size> _decodeImageSize(String path) => readImageSize(path);

  Point2D pointFor(CropHandle handle) => switch (handle) {
    CropHandle.topLeft => _quad.topLeft,
    CropHandle.topRight => _quad.topRight,
    CropHandle.bottomRight => _quad.bottomRight,
    CropHandle.bottomLeft => _quad.bottomLeft,
    CropHandle.top => _mid(_quad.topLeft, _quad.topRight),
    CropHandle.right => _mid(_quad.topRight, _quad.bottomRight),
    CropHandle.bottom => _mid(_quad.bottomLeft, _quad.bottomRight),
    CropHandle.left => _mid(_quad.topLeft, _quad.bottomLeft),
  };

  static Point2D _mid(Point2D a, Point2D b) =>
      Point2D(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2);

  static Point2D _clampPoint(Point2D p) =>
      Point2D(x: p.x.clamp(0.0, 1.0), y: p.y.clamp(0.0, 1.0));

  static Point2D _offset(Point2D p, ui.Offset d) =>
      _clampPoint(Point2D(x: p.x + d.dx, y: p.y + d.dy));

  /// Line-line intersection matching Tap Scanner `d52.G(A,B,C,D)`:
  /// intersection of line AB with line CD.
  static Point2D? _intersect(Point2D a, Point2D b, Point2D c, Point2D d) {
    final abx = b.x - a.x;
    final aby = b.y - a.y;
    final cdx = d.x - c.x;
    final cdy = d.y - c.y;
    final acx = c.x - a.x;
    final acy = c.y - a.y;
    final denom = abx * cdy - aby * cdx;
    if (denom.abs() < 1e-9) return null;
    final t = (acx * cdy - acy * cdx) / denom;
    return Point2D(x: a.x + t * abx, y: a.y + t * aby);
  }

  static double _dist(Point2D a, Point2D b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  bool _isValid(Quad q) {
    if (_dist(q.topLeft, q.topRight) < minEdge) return false;
    if (_dist(q.topRight, q.bottomRight) < minEdge) return false;
    if (_dist(q.bottomRight, q.bottomLeft) < minEdge) return false;
    if (_dist(q.bottomLeft, q.topLeft) < minEdge) return false;
    // Reject inverted / crossed quads (negative cross of adjacent edges).
    double cross(Point2D o, Point2D a, Point2D b) =>
        (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
    final c1 = cross(q.topLeft, q.topRight, q.bottomRight);
    final c2 = cross(q.topRight, q.bottomRight, q.bottomLeft);
    final c3 = cross(q.bottomRight, q.bottomLeft, q.topLeft);
    final c4 = cross(q.bottomLeft, q.topLeft, q.topRight);
    final allPos = c1 > 0 && c2 > 0 && c3 > 0 && c4 > 0;
    final allNeg = c1 < 0 && c2 < 0 && c3 < 0 && c4 < 0;
    return allPos || allNeg;
  }

  void _setQuadIfValid(Quad next) {
    final clamped = Quad(
      topLeft: _clampPoint(next.topLeft),
      topRight: _clampPoint(next.topRight),
      bottomRight: _clampPoint(next.bottomRight),
      bottomLeft: _clampPoint(next.bottomLeft),
    );
    if (!_isValid(clamped)) return;
    _quad = clamped;
    notifyListeners();
  }

  /// Moves a corner or edge handle by a normalized (0..1-space) delta.
  ///
  /// Edge drags match Tap Scanner: the moved edge is shifted (axis-locked
  /// to the dominant finger delta), then each endpoint is the intersection
  /// of that shifted edge with the two adjacent sides — so corners slide
  /// along the neighboring edges instead of shearing independently.
  void dragHandle(CropHandle handle, ui.Offset normalizedDelta) {
    final q = _quad;
    switch (handle) {
      case CropHandle.topLeft:
        _setQuadIfValid(
          q.copyWith(topLeft: _offset(q.topLeft, normalizedDelta)),
        );
      case CropHandle.topRight:
        _setQuadIfValid(
          q.copyWith(topRight: _offset(q.topRight, normalizedDelta)),
        );
      case CropHandle.bottomRight:
        _setQuadIfValid(
          q.copyWith(bottomRight: _offset(q.bottomRight, normalizedDelta)),
        );
      case CropHandle.bottomLeft:
        _setQuadIfValid(
          q.copyWith(bottomLeft: _offset(q.bottomLeft, normalizedDelta)),
        );
      case CropHandle.top:
        _dragEdge(
          delta: normalizedDelta,
          horizontal: true,
          a: q.topLeft,
          b: q.topRight,
          sideAStart: q.topLeft,
          sideAEnd: q.bottomLeft,
          sideBStart: q.topRight,
          sideBEnd: q.bottomRight,
          apply: (na, nb) => q.copyWith(topLeft: na, topRight: nb),
        );
      case CropHandle.bottom:
        _dragEdge(
          delta: normalizedDelta,
          horizontal: true,
          a: q.bottomLeft,
          b: q.bottomRight,
          sideAStart: q.bottomLeft,
          sideAEnd: q.topLeft,
          sideBStart: q.bottomRight,
          sideBEnd: q.topRight,
          apply: (na, nb) => q.copyWith(bottomLeft: na, bottomRight: nb),
        );
      case CropHandle.left:
        _dragEdge(
          delta: normalizedDelta,
          horizontal: false,
          a: q.topLeft,
          b: q.bottomLeft,
          sideAStart: q.topLeft,
          sideAEnd: q.topRight,
          sideBStart: q.bottomLeft,
          sideBEnd: q.bottomRight,
          apply: (na, nb) => q.copyWith(topLeft: na, bottomLeft: nb),
        );
      case CropHandle.right:
        _dragEdge(
          delta: normalizedDelta,
          horizontal: false,
          a: q.topRight,
          b: q.bottomRight,
          sideAStart: q.topRight,
          sideAEnd: q.topLeft,
          sideBStart: q.bottomRight,
          sideBEnd: q.bottomLeft,
          apply: (na, nb) => q.copyWith(topRight: na, bottomRight: nb),
        );
    }
  }

  void _dragEdge({
    required ui.Offset delta,
    required bool horizontal,
    required Point2D a,
    required Point2D b,
    required Point2D sideAStart,
    required Point2D sideAEnd,
    required Point2D sideBStart,
    required Point2D sideBEnd,
    required Quad Function(Point2D na, Point2D nb) apply,
  }) {
    // Tap Scanner locks the tangential axis for edge grabs (BOTTOM uses
    // dy only, LEFT/RIGHT use dx only) so the edge stays parallel to its
    // prior orientation and corners slide on the adjacent sides.
    final locked = horizontal ? ui.Offset(0, delta.dy) : ui.Offset(delta.dx, 0);
    if (locked.dx == 0 && locked.dy == 0) return;

    final movedA = Point2D(x: a.x + locked.dx, y: a.y + locked.dy);
    final movedB = Point2D(x: b.x + locked.dx, y: b.y + locked.dy);

    final na =
        _intersect(movedA, movedB, sideAStart, sideAEnd) ?? _clampPoint(movedA);
    final nb =
        _intersect(movedA, movedB, sideBStart, sideBEnd) ?? _clampPoint(movedB);

    _setQuadIfValid(apply(na, nb));
  }

  /// Legacy name kept so existing call sites / tests compile.
  void dragCorner(CropHandle corner, ui.Offset normalizedDelta) =>
      dragHandle(corner, normalizedDelta);

  /// Translates the whole quad (Tap Scanner CENTER), clamping as a unit.
  void moveQuad(ui.Offset normalizedDelta) {
    var minDx = double.negativeInfinity;
    var maxDx = double.infinity;
    var minDy = double.negativeInfinity;
    var maxDy = double.infinity;
    for (final p in _quad.points) {
      minDx = math.max(minDx, -p.x);
      maxDx = math.min(maxDx, 1.0 - p.x);
      minDy = math.max(minDy, -p.y);
      maxDy = math.min(maxDy, 1.0 - p.y);
    }
    final d = ui.Offset(
      normalizedDelta.dx.clamp(minDx, maxDx),
      normalizedDelta.dy.clamp(minDy, maxDy),
    );
    if (d.dx == 0 && d.dy == 0) return;
    _setQuadIfValid(
      Quad(
        topLeft: _offset(_quad.topLeft, d),
        topRight: _offset(_quad.topRight, d),
        bottomRight: _offset(_quad.bottomRight, d),
        bottomLeft: _offset(_quad.bottomLeft, d),
      ),
    );
  }

  void resetToFullFrame() {
    _quad = Quad.fullFrame;
    notifyListeners();
  }

  /// Extra 90° turns applied in this edit session (on top of the page's
  /// persisted [ScanPage.rotationDegrees]).
  int _sessionRotation = 0;

  /// Quarter-turns to rotate the crop canvas for display (0..3).
  int get displayQuarterTurns {
    final total = (_page?.rotationDegrees ?? 0) + _sessionRotation;
    return ((total ~/ 90) % 4 + 4) % 4;
  }

  void rotateLeft() {
    _sessionRotation -= 90;
    notifyListeners();
  }

  void rotateRight() {
    _sessionRotation += 90;
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
      final updated = await _capturePageUseCase.reprocessPage(
        page,
        cropPoints: _quad,
        rotationDegrees:
            (((page.rotationDegrees + _sessionRotation) % 360) + 360) % 360,
      );
      final path = updated.processedImagePath;
      if (path != null) {
        try {
          await FileImage(File(path)).evict();
        } on Object {
          // No painting binding in plain unit tests.
        }
      }
      _page = updated;
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
