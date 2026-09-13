import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

import '../../../domain/models/geometry.dart';

/// Decode a still, bake EXIF orientation, and find a document quad.
/// Top-level so [compute] can run it on a background isolate.
Quad? detectDocumentQuadFromPath(String imagePath) {
  try {
    final bytes = File(imagePath).readAsBytesSync();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    return detectDocumentQuad(img.bakeOrientation(decoded));
  } on Object {
    // Isolate failures here abort the whole capture; degrade to "no quad"
    // so the caller can keep the original still (SPEC 9.7).
    return null;
  }
}

/// Find a document quadrilateral in an already-decoded, orientation-baked
/// image. Shared by [DartPageDetectionProvider] and the enhancement isolate
/// so capture only decodes the JPEG once.
///
/// Returns null for a full-bleed page (no surrounding desk) and when a
/// paper/background split is visible but corners cannot be fitted
/// confidently. Callers must not invent a crop from the static capture
/// guide — uncertain pages go to manual corner correction.
Quad? detectDocumentQuad(img.Image upright, {bool splitOpenBook = true}) {
  try {
    final scale = 400 / math.max(upright.width, upright.height);
    final small = img.copyResize(
      upright,
      width: (upright.width * scale).round().clamp(1, upright.width),
      height: (upright.height * scale).round().clamp(1, upright.height),
    );
    final gray = img.grayscale(small);
    final blurred = img.gaussianBlur(gray, radius: 2);

    final contour = _detectContourQuad(blurred, splitOpenBook: splitOpenBook);
    if (contour.quad != null) return contour.quad;

    // Uncertain paper (visible split but no confident 4-corner fit) and
    // full-bleed pages both return null. Callers send the user to manual
    // corner correction instead of inventing a crop.
    return null;
  } on Object {
    return null;
  }
}

/// Paper-vs-background mask → largest component → convex hull → 4 corners.
/// Tries both polarities (bright page on a dark desk, or the reverse) and
/// keeps the higher-scoring quad.
({Quad? quad, bool hadSplit}) _detectContourQuad(
  img.Image gray, {
  bool splitOpenBook = true,
}) {
  final w = gray.width;
  final h = gray.height;
  final luma = List<int>.filled(w * h, 0);
  final hist = List<int>.filled(256, 0);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final v = gray.getPixel(x, y).r.toInt().clamp(0, 255);
      luma[y * w + x] = v;
      hist[v]++;
    }
  }

  final threshold = _otsu(hist, w * h);
  Quad? best;
  var bestScore = 0.0;
  var hadSplit = false;
  for (final brightIsPaper in const [true, false]) {
    final mask = List<int>.filled(w * h, 0);
    var paperCount = 0;
    for (var i = 0; i < luma.length; i++) {
      final isPaper = brightIsPaper
          ? luma[i] >= threshold
          : luma[i] < threshold;
      if (isPaper) {
        mask[i] = 1;
        paperCount++;
      }
    }
    // No real foreground/background split — the whole frame is one class.
    if (paperCount < w * h * 0.25 || paperCount > w * h * 0.985) continue;

    final closed = _erode(_dilate(mask, w, h, 4), w, h, 4);
    final component = _largestComponent(closed, w, h);
    if (component == null) continue;
    if (component.length < w * h * 0.25) continue;
    if (component.length > w * h * 0.95) continue;
    hadSplit = true;

    // An open book is one connected paper blob. Fitting 4 corners to that
    // hexagon puts a vertex on the gutter, which cuts through the page the
    // user framed (seen on-device: the crop overlay sat in the middle of
    // the right-hand page). If a dark vertical gutter is present, score
    // each half separately and keep the page closest to the frame center.
    final candidates = <List<int>>[];
    final gutterX = splitOpenBook ? _gutterColumn(component, luma, w, h) : null;
    if (gutterX != null) {
      final left = [
        for (final i in component)
          if (i % w < gutterX) i,
      ];
      final right = [
        for (final i in component)
          if (i % w >= gutterX) i,
      ];
      if (left.length >= w * h * 0.12) candidates.add(left);
      if (right.length >= w * h * 0.12) candidates.add(right);
    }
    if (candidates.isEmpty) candidates.add(component);

    for (final pixels in candidates) {
      final scored = _scorePixelsAsQuad(pixels, w, h);
      if (scored == null) continue;
      if (scored.score > bestScore) {
        bestScore = scored.score;
        best = scored.quad;
      }
    }
  }
  return (quad: best, hadSplit: hadSplit);
}

({Quad quad, double score})? _scorePixelsAsQuad(
  List<int> pixels,
  int w,
  int h,
) {
  final subsetMask = List<int>.filled(w * h, 0);
  var sumX = 0.0;
  var sumY = 0.0;
  for (final i in pixels) {
    subsetMask[i] = 1;
    sumX += i % w;
    sumY += i ~/ w;
  }
  final boundary = _boundaryPoints(pixels, subsetMask, w, h);
  if (boundary.length < 4) return null;

  final hull = _convexHull(boundary);
  final corners = _approximateQuad(hull);
  if (corners.length != 4) return null;
  if (!_cornersDistinct(corners, minDistance: math.min(w, h) * 0.08)) {
    return null;
  }

  final hullArea = _polygonArea(hull);
  final quadArea = _polygonArea(corners);
  if (hullArea < 1 || quadArea / hullArea < 0.82) return null;

  final quad = _orderedNormalizedQuad(corners, w, h);
  if (quad == null || _isNearlyFullFrame(quad)) return null;

  final area = _normalizedQuadArea(quad);
  if (area < 0.12 || area > 0.98) return null;

  final cx = (sumX / pixels.length) / w - 0.5;
  final cy = (sumY / pixels.length) / h - 0.5;
  final centerBias = (1.0 - 2.0 * math.sqrt(cx * cx + cy * cy)).clamp(
    0.15,
    1.0,
  );
  final score = area * (quadArea / hullArea) * centerBias;
  return (quad: quad, score: score);
}

/// Dark vertical valley (book gutter / spine) inside a paper component, or
/// null if the region is a single page. Column mean luma of paper pixels;
/// a gutter is a column in the inner 50% of the blob that is clearly
/// darker than the page body, with a real page on both sides.
int? _gutterColumn(List<int> pixels, List<int> luma, int w, int h) {
  var minX = w;
  var maxX = 0;
  final colSum = List<double>.filled(w, 0);
  final colCount = List<int>.filled(w, 0);
  for (final i in pixels) {
    final x = i % w;
    if (x < minX) minX = x;
    if (x > maxX) maxX = x;
    colSum[x] += luma[i];
    colCount[x]++;
  }
  final width = maxX - minX;
  if (width < w * 0.35) return null;

  final bandStart = minX + (width * 0.25).round();
  final bandEnd = minX + (width * 0.75).round();
  if (bandEnd <= bandStart) return null;

  final means = <double>[];
  for (var x = bandStart; x < bandEnd; x++) {
    if (colCount[x] == 0) continue;
    means.add(colSum[x] / colCount[x]);
  }
  if (means.length < 8) return null;
  final sorted = [...means]..sort();
  final median = sorted[sorted.length ~/ 2];
  if (median < 1) return null;

  var bestX = -1;
  var bestMean = median;
  for (var x = bandStart; x < bandEnd; x++) {
    if (colCount[x] == 0) continue;
    final mean = colSum[x] / colCount[x];
    if (mean < bestMean) {
      bestMean = mean;
      bestX = x;
    }
  }
  // Book gutter is a crease/shadow, not a printed line: require a clearly
  // darker column than the page body so a text column doesn't split a
  // single document.
  if (bestX < 0 || bestMean > median * 0.72) return null;

  var leftCount = 0;
  var rightCount = 0;
  for (final i in pixels) {
    if (i % w < bestX) {
      leftCount++;
    } else {
      rightCount++;
    }
  }
  if (leftCount < pixels.length * 0.18 || rightCount < pixels.length * 0.18) {
    return null;
  }
  return bestX;
}

/// Scan inward from each side for the first strong gradient, fit a line
/// per side, and intersect. Finds cream-on-wood / weak-blob pages that
/// the paper-mask path cannot turn into a convex quad.
Quad? _detectEdgeLinesQuad(img.Image gray) {
  final w = gray.width;
  final h = gray.height;
  if (w < 24 || h < 24) return null;

  final mag = List<double>.filled(w * h, 0);
  var maxMag = 0.0;
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final gx =
          gray.getPixel(x + 1, y).r.toDouble() -
          gray.getPixel(x - 1, y).r.toDouble();
      final gy =
          gray.getPixel(x, y + 1).r.toDouble() -
          gray.getPixel(x, y - 1).r.toDouble();
      final m = gx.abs() + gy.abs();
      mag[y * w + x] = m;
      if (m > maxMag) maxMag = m;
    }
  }
  if (maxMag < 12) return null;
  final thresh = maxMag * 0.18;

  final top = _scanInward(
    mag,
    w,
    h,
    thresh,
    alongX: true,
    fromStart: true,
    maxDepth: (h * 0.55).round(),
  );
  final bottom = _scanInward(
    mag,
    w,
    h,
    thresh,
    alongX: true,
    fromStart: false,
    maxDepth: (h * 0.55).round(),
  );
  final left = _scanInward(
    mag,
    w,
    h,
    thresh,
    alongX: false,
    fromStart: true,
    maxDepth: (w * 0.55).round(),
  );
  final right = _scanInward(
    mag,
    w,
    h,
    thresh,
    alongX: false,
    fromStart: false,
    maxDepth: (w * 0.55).round(),
  );

  final topLine = _fitLine(top, alongX: true);
  final bottomLine = _fitLine(bottom, alongX: true);
  final leftLine = _fitLine(left, alongX: false);
  final rightLine = _fitLine(right, alongX: false);
  if (topLine == null ||
      bottomLine == null ||
      leftLine == null ||
      rightLine == null) {
    return null;
  }

  final tl = topLine.intersect(leftLine);
  final tr = topLine.intersect(rightLine);
  final br = bottomLine.intersect(rightLine);
  final bl = bottomLine.intersect(leftLine);
  if (tl == null || tr == null || br == null || bl == null) return null;

  final corners = [
    _Pt(tl.$1, tl.$2),
    _Pt(tr.$1, tr.$2),
    _Pt(br.$1, br.$2),
    _Pt(bl.$1, bl.$2),
  ];
  if (!_cornersDistinct(corners, minDistance: math.min(w, h) * 0.08)) {
    return null;
  }

  final quad = _orderedNormalizedQuad(corners, w, h);
  if (quad == null || _isNearlyFullFrame(quad)) return null;
  final area = _normalizedQuadArea(quad);
  if (area < 0.12 || area > 0.98) return null;
  return quad;
}

List<_Pt> _scanInward(
  List<double> mag,
  int w,
  int h,
  double thresh, {
  required bool alongX,
  required bool fromStart,
  required int maxDepth,
}) {
  final pts = <_Pt>[];
  if (alongX) {
    for (var x = 4; x < w - 4; x += 2) {
      if (fromStart) {
        final limit = math.min(h - 2, maxDepth);
        for (var y = 2; y < limit; y++) {
          if (_isLocalMax(mag, w, x, y, thresh, alongY: true)) {
            pts.add(_Pt(x.toDouble(), y.toDouble()));
            break;
          }
        }
      } else {
        final limit = math.max(1, h - maxDepth);
        for (var y = h - 3; y > limit; y--) {
          if (_isLocalMax(mag, w, x, y, thresh, alongY: true)) {
            pts.add(_Pt(x.toDouble(), y.toDouble()));
            break;
          }
        }
      }
    }
  } else {
    for (var y = 4; y < h - 4; y += 2) {
      if (fromStart) {
        final limit = math.min(w - 2, maxDepth);
        for (var x = 2; x < limit; x++) {
          if (_isLocalMax(mag, w, x, y, thresh, alongY: false)) {
            pts.add(_Pt(x.toDouble(), y.toDouble()));
            break;
          }
        }
      } else {
        final limit = math.max(1, w - maxDepth);
        for (var x = w - 3; x > limit; x--) {
          if (_isLocalMax(mag, w, x, y, thresh, alongY: false)) {
            pts.add(_Pt(x.toDouble(), y.toDouble()));
            break;
          }
        }
      }
    }
  }
  return pts;
}

bool _isLocalMax(
  List<double> mag,
  int w,
  int x,
  int y,
  double thresh, {
  required bool alongY,
}) {
  final i = y * w + x;
  final v = mag[i];
  if (v < thresh) return false;
  if (alongY) {
    return v >= mag[i - w] && v >= mag[i + w];
  }
  return v >= mag[i - 1] && v >= mag[i + 1];
}

_Line? _fitLine(List<_Pt> pts, {required bool alongX}) {
  if (pts.length < 8) return null;
  var sumA = 0.0;
  var sumB = 0.0;
  var sumAB = 0.0;
  var sumA2 = 0.0;
  final n = pts.length.toDouble();
  for (final p in pts) {
    final a = alongX ? p.x : p.y;
    final b = alongX ? p.y : p.x;
    sumA += a;
    sumB += b;
    sumAB += a * b;
    sumA2 += a * a;
  }
  final denom = n * sumA2 - sumA * sumA;
  if (denom.abs() < 1e-6) return null;
  final slope = (n * sumAB - sumA * sumB) / denom;
  final intercept = (sumB - slope * sumA) / n;
  return _Line(intercept: intercept, slope: slope, alongX: alongX);
}

class _Line {
  const _Line({
    required this.intercept,
    required this.slope,
    required this.alongX,
  });

  final double intercept;
  final double slope;
  final bool alongX;

  (double, double)? intersect(_Line other) {
    if (alongX && other.alongX) {
      final db = slope - other.slope;
      if (db.abs() < 1e-9) return null;
      final x = (other.intercept - intercept) / db;
      return (x, intercept + slope * x);
    }
    if (!alongX && !other.alongX) {
      final db = slope - other.slope;
      if (db.abs() < 1e-9) return null;
      final y = (other.intercept - intercept) / db;
      return (intercept + slope * y, y);
    }
    if (alongX && !other.alongX) {
      final denom = 1 - other.slope * slope;
      if (denom.abs() < 1e-9) return null;
      final x = (other.intercept + other.slope * intercept) / denom;
      return (x, intercept + slope * x);
    }
    return other.intersect(this);
  }
}

/// Original Sobel + projection-profile path, kept as a fallback when the
/// contour detector cannot find a confident quad (low-contrast page vs
/// background, busy scene, etc.). Axis-aligned only.
Quad? _detectAxisAlignedQuad(img.Image gray) {
  final edges = img.sobel(gray);
  final w = edges.width;
  final h = edges.height;
  final rowEnergy = List<double>.filled(h, 0);
  final colEnergy = List<double>.filled(w, 0);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final v = edges.getPixel(x, y).r.toDouble();
      rowEnergy[y] += v;
      colEnergy[x] += v;
    }
  }

  // 20%-of-peak (not 35%): a dense line of text inside the page routinely
  // has stronger Sobel energy than the true paper-to-background boundary,
  // so a high relative threshold walks the scan past the real edge and
  // stops at the first text line instead -- observed on-device as page
  // edges being cropped into real content. Mirrors FrameMath.kt.
  final rowThreshold = _peakThreshold(rowEnergy, 0.2);
  final colThreshold = _peakThreshold(colEnergy, 0.2);

  var top = 0;
  while (top < h - 1 && rowEnergy[top] < rowThreshold) {
    top++;
  }
  var bottom = h - 1;
  while (bottom > 0 && rowEnergy[bottom] < rowThreshold) {
    bottom--;
  }
  var left = 0;
  while (left < w - 1 && colEnergy[left] < colThreshold) {
    left++;
  }
  var right = w - 1;
  while (right > 0 && colEnergy[right] < colThreshold) {
    right--;
  }

  if (right - left < w * 0.3 || bottom - top < h * 0.3) {
    return null;
  }

  // Safety margin: this fallback still localizes to the first strong row/
  // column of edge energy, so it can clip text. Bias outward. The contour
  // path above does not use this margin — it fits the paper region itself.
  final marginX = w * 0.03;
  final marginY = h * 0.03;
  final l = ((left - marginX) / w).clamp(0.0, 1.0);
  final r = ((right + marginX) / w).clamp(0.0, 1.0);
  final t = ((top - marginY) / h).clamp(0.0, 1.0);
  final b = ((bottom + marginY) / h).clamp(0.0, 1.0);

  final quad = Quad(
    topLeft: Point2D(x: l, y: t),
    topRight: Point2D(x: r, y: t),
    bottomRight: Point2D(x: r, y: b),
    bottomLeft: Point2D(x: l, y: b),
  );
  if (_isNearlyFullFrame(quad)) return null;
  return quad;
}

int _otsu(List<int> hist, int total) {
  var sum = 0;
  for (var i = 0; i < 256; i++) {
    sum += i * hist[i];
  }
  var sumB = 0;
  var wB = 0;
  var maxVar = 0.0;
  var threshold = 128;
  for (var t = 0; t < 256; t++) {
    wB += hist[t];
    if (wB == 0) continue;
    final wF = total - wB;
    if (wF == 0) break;
    sumB += t * hist[t];
    final mB = sumB / wB;
    final mF = (sum - sumB) / wF;
    final between = wB * wF * (mB - mF) * (mB - mF);
    if (between > maxVar) {
      maxVar = between;
      threshold = t;
    }
  }
  return threshold;
}

List<int> _dilate(List<int> src, int w, int h, int radius) {
  final out = List<int>.filled(w * h, 0);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final y0 = math.max(0, y - radius);
      final y1 = math.min(h - 1, y + radius);
      final x0 = math.max(0, x - radius);
      final x1 = math.min(w - 1, x + radius);
      var found = 0;
      outer:
      for (var yy = y0; yy <= y1; yy++) {
        for (var xx = x0; xx <= x1; xx++) {
          if (src[yy * w + xx] != 0) {
            found = 1;
            break outer;
          }
        }
      }
      out[y * w + x] = found;
    }
  }
  return out;
}

List<int> _erode(List<int> src, int w, int h, int radius) {
  final out = List<int>.filled(w * h, 0);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final y0 = math.max(0, y - radius);
      final y1 = math.min(h - 1, y + radius);
      final x0 = math.max(0, x - radius);
      final x1 = math.min(w - 1, x + radius);
      var all = 1;
      outer:
      for (var yy = y0; yy <= y1; yy++) {
        for (var xx = x0; xx <= x1; xx++) {
          if (src[yy * w + xx] == 0) {
            all = 0;
            break outer;
          }
        }
      }
      out[y * w + x] = all;
    }
  }
  return out;
}

List<int>? _largestComponent(List<int> mask, int w, int h) {
  final visited = List<bool>.filled(w * h, false);
  List<int>? best;
  final stack = <int>[];
  for (var i = 0; i < mask.length; i++) {
    if (mask[i] == 0 || visited[i]) continue;
    stack
      ..clear()
      ..add(i);
    visited[i] = true;
    final pixels = <int>[];
    while (stack.isNotEmpty) {
      final cur = stack.removeLast();
      pixels.add(cur);
      final x = cur % w;
      final y = cur ~/ w;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = x + dx;
          final ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
          final ni = ny * w + nx;
          if (visited[ni] || mask[ni] == 0) continue;
          visited[ni] = true;
          stack.add(ni);
        }
      }
    }
    if (best == null || pixels.length > best.length) best = pixels;
  }
  return best;
}

List<_Pt> _boundaryPoints(List<int> pixels, List<int> mask, int w, int h) {
  final pts = <_Pt>[];
  for (final i in pixels) {
    final x = i % w;
    final y = i ~/ w;
    final onEdge =
        x == 0 ||
        y == 0 ||
        x == w - 1 ||
        y == h - 1 ||
        mask[i - 1] == 0 ||
        mask[i + 1] == 0 ||
        mask[i - w] == 0 ||
        mask[i + w] == 0;
    if (onEdge) pts.add(_Pt(x.toDouble(), y.toDouble()));
  }
  return pts;
}

List<_Pt> _convexHull(List<_Pt> points) {
  if (points.length < 3) return List<_Pt>.from(points);
  final sorted = [...points]
    ..sort((a, b) {
      final cx = a.x.compareTo(b.x);
      return cx != 0 ? cx : a.y.compareTo(b.y);
    });
  final lower = <_Pt>[];
  for (final p in sorted) {
    while (lower.length >= 2 &&
        _cross(lower[lower.length - 2], lower.last, p) <= 0) {
      lower.removeLast();
    }
    lower.add(p);
  }
  final upper = <_Pt>[];
  for (var i = sorted.length - 1; i >= 0; i--) {
    final p = sorted[i];
    while (upper.length >= 2 &&
        _cross(upper[upper.length - 2], upper.last, p) <= 0) {
      upper.removeLast();
    }
    upper.add(p);
  }
  if (lower.isNotEmpty) lower.removeLast();
  if (upper.isNotEmpty) upper.removeLast();
  return [...lower, ...upper];
}

List<_Pt> _approximateQuad(List<_Pt> hull) {
  if (hull.length < 4) return const [];
  final pts = [...hull];
  while (pts.length > 4) {
    var minIdx = 0;
    var minArea = double.infinity;
    for (var i = 0; i < pts.length; i++) {
      final prev = pts[(i - 1 + pts.length) % pts.length];
      final curr = pts[i];
      final next = pts[(i + 1) % pts.length];
      final area = _triangleArea(prev, curr, next);
      if (area < minArea) {
        minArea = area;
        minIdx = i;
      }
    }
    pts.removeAt(minIdx);
  }
  return pts;
}

Quad? _orderedNormalizedQuad(List<_Pt> corners, int w, int h) {
  _Pt? tl, tr, br, bl;
  var minSum = double.infinity;
  var maxSum = -double.infinity;
  var minDiff = double.infinity;
  var maxDiff = -double.infinity;
  for (final p in corners) {
    final sum = p.x + p.y;
    final diff = p.x - p.y;
    if (sum < minSum) {
      minSum = sum;
      tl = p;
    }
    if (sum > maxSum) {
      maxSum = sum;
      br = p;
    }
    if (diff > maxDiff) {
      maxDiff = diff;
      tr = p;
    }
    if (diff < minDiff) {
      minDiff = diff;
      bl = p;
    }
  }
  if (tl == null || tr == null || br == null || bl == null) return null;
  // Degenerate assignment: two labels landed on the same vertex.
  if (identical(tl, tr) ||
      identical(tr, br) ||
      identical(br, bl) ||
      identical(bl, tl)) {
    return null;
  }

  Point2D n(_Pt p) =>
      Point2D(x: (p.x / w).clamp(0.0, 1.0), y: (p.y / h).clamp(0.0, 1.0));

  // Tiny outward nudge so bilinear sampling at the paper edge during
  // rectify does not clip a 1px sliver of content. 0.8% of the centroid
  // vector is ~3px on the 400px analysis buffer — far less than the 3%
  // AABB safety margin, so the crop still looks tight.
  final tlN = n(tl);
  final trN = n(tr);
  final brN = n(br);
  final blN = n(bl);
  final cx = (tlN.x + trN.x + brN.x + blN.x) / 4;
  final cy = (tlN.y + trN.y + brN.y + blN.y) / 4;
  Point2D expand(Point2D p) => Point2D(
    x: (p.x + (p.x - cx) * 0.008).clamp(0.0, 1.0),
    y: (p.y + (p.y - cy) * 0.008).clamp(0.0, 1.0),
  );

  return Quad(
    topLeft: expand(tlN),
    topRight: expand(trN),
    bottomRight: expand(brN),
    bottomLeft: expand(blN),
  );
}

bool _cornersDistinct(List<_Pt> corners, {required double minDistance}) {
  for (var i = 0; i < corners.length; i++) {
    for (var j = i + 1; j < corners.length; j++) {
      final dx = corners[i].x - corners[j].x;
      final dy = corners[i].y - corners[j].y;
      if (math.sqrt(dx * dx + dy * dy) < minDistance) return false;
    }
  }
  return true;
}

bool _isNearlyFullFrame(Quad quad) =>
    quad.topLeft.x < 0.03 &&
    quad.topLeft.y < 0.03 &&
    quad.topRight.x > 0.97 &&
    quad.topRight.y < 0.03 &&
    quad.bottomRight.x > 0.97 &&
    quad.bottomRight.y > 0.97 &&
    quad.bottomLeft.x < 0.03 &&
    quad.bottomLeft.y > 0.97;

double _normalizedQuadArea(Quad q) => _polygonArea([
  _Pt(q.topLeft.x, q.topLeft.y),
  _Pt(q.topRight.x, q.topRight.y),
  _Pt(q.bottomRight.x, q.bottomRight.y),
  _Pt(q.bottomLeft.x, q.bottomLeft.y),
]);

double _polygonArea(List<_Pt> pts) {
  if (pts.length < 3) return 0;
  var sum = 0.0;
  for (var i = 0; i < pts.length; i++) {
    final a = pts[i];
    final b = pts[(i + 1) % pts.length];
    sum += a.x * b.y - b.x * a.y;
  }
  return sum.abs() / 2;
}

double _triangleArea(_Pt a, _Pt b, _Pt c) =>
    ((a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y)).abs()) / 2;

double _cross(_Pt o, _Pt a, _Pt b) =>
    (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);

double _peakThreshold(List<double> values, double fraction) {
  final sorted = [...values]..sort();
  if (sorted.isEmpty) return 0;
  return sorted.last * fraction;
}

class _Pt {
  const _Pt(this.x, this.y);
  final double x;
  final double y;
}
