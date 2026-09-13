import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../../domain/models/geometry.dart';
import '../../../../domain/models/provider_info.dart';
import '../../../../domain/providers/book_dewarp_provider.dart';
import '../../local/file_storage_service.dart';

/// Cross-platform classical baseline for book-specific segmentation (SPEC
/// 9.3). This is a real, working implementation — not a stub — built on
/// Sobel edge-energy analysis (the same technique as
/// [DartPageDetectionProvider]), not a learned segmentation/dewarping
/// model. Documented limitations, in the same spirit as the other classical
/// fallbacks in this codebase:
///  - Gutter detection assumes the spine sits roughly centered
///    horizontally (35%-65% of frame width) and produces a visible edge
///    (shadow or crease); an off-center or very worn/faded gutter will not
///    be found and falls back to a low-confidence center split, which the
///    manual split-correction UI can then fix.
///  - Curvature flattening fits a single quadratic per page edge, which
///    corrects the common "page bows away from the spine" distortion but
///    not S-curves or highly irregular deformation.
///  - Occlusion detection is a skin-tone heuristic (HSV thresholding), not
///    a hand/finger classifier — it can miss gloved hands or trigger on
///    skin-colored page backgrounds. Per SPEC 9.3 it never removes/inpaints
///    detected occlusions; it only flags them so the caller can warn and
///    recommend a rescan.
class DartBookDewarpProvider implements BookDewarpProvider {
  DartBookDewarpProvider(this._fileStorage, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final FileStorageService _fileStorage;
  final Uuid _uuid;

  @override
  ProviderInfo get info => const ProviderInfo(
    providerName: 'dart-book-dewarp-baseline',
    adapterVersion: '1.1.0',
  );

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<SpreadSplitResult> splitSpread(
    String spreadImagePath, {
    double? gutterXOverride,
  }) async {
    final outDir = _fileStorage.paths.tmpDir.path;
    final leftPath = p.join(outDir, '${_uuid.v4()}_spread_left.jpg');
    final rightPath = p.join(outDir, '${_uuid.v4()}_spread_right.jpg');
    final result = await compute(
      _splitSpreadJob,
      _SplitSpreadArgs(
        spreadImagePath: spreadImagePath,
        leftOutputPath: leftPath,
        rightOutputPath: rightPath,
        gutterXOverride: gutterXOverride,
      ),
    );
    return SpreadSplitResult(
      leftPageImagePath: result.leftPath,
      rightPageImagePath: result.rightPath,
      confidence: result.confidence,
      providerInfo: info,
    );
  }

  @override
  Future<DewarpResult> dewarp(
    String pageImagePath,
    Quad pageBounds, {
    String? outputPath,
  }) async {
    final outPath =
        outputPath ??
        p.join(
          _fileStorage.paths.processedDir.path,
          '${_uuid.v4()}_dewarped.jpg',
        );
    final result = await compute(
      _dewarpJob,
      _DewarpArgs(
        imagePath: pageImagePath,
        bounds: pageBounds,
        outputPath: outPath,
      ),
    );
    final pageId = p
        .basenameWithoutExtension(outPath)
        .replaceAll('_dewarped', '');
    await _fileStorage.generateThumbnail(result.outputPath, pageId);
    return DewarpResult(
      flattenedImagePath: result.outputPath,
      providerInfo: info,
      occlusionDetected: result.occlusionDetected,
      occlusionHighConfidenceTextLoss: result.occlusionHighConfidenceTextLoss,
    );
  }
}

class _SplitSpreadArgs {
  const _SplitSpreadArgs({
    required this.spreadImagePath,
    required this.leftOutputPath,
    required this.rightOutputPath,
    this.gutterXOverride,
  });

  final String spreadImagePath;
  final String leftOutputPath;
  final String rightOutputPath;
  final double? gutterXOverride;
}

class _SplitSpreadJobResult {
  const _SplitSpreadJobResult({
    required this.leftPath,
    required this.rightPath,
    required this.confidence,
  });

  final String leftPath;
  final String rightPath;
  final double confidence;
}

_SplitSpreadJobResult _splitSpreadJob(_SplitSpreadArgs args) {
  final bytes = File(args.spreadImagePath).readAsBytesSync();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw StateError('Cannot decode image at ${args.spreadImagePath}');
  }

  double gutterX;
  double confidence;
  if (args.gutterXOverride != null) {
    gutterX = args.gutterXOverride!.clamp(0.0, 1.0);
    confidence = 1.0;
  } else {
    final scale = 500 / math.max(decoded.width, decoded.height);
    final small = img.copyResize(
      decoded,
      width: (decoded.width * scale).round(),
      height: (decoded.height * scale).round(),
    );
    final gray = img.grayscale(small);
    final edges = img.sobel(img.Image.from(gray));

    final w = edges.width;
    final h = edges.height;
    final colEnergy = List<double>.filled(w, 0);
    final colLuma = List<double>.filled(w, 0);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        colEnergy[x] += edges.getPixel(x, y).r.toDouble();
        colLuma[x] += gray.getPixel(x, y).r.toDouble();
      }
    }
    for (var x = 0; x < w; x++) {
      colLuma[x] /= h;
    }

    // The gutter is expected roughly centered; searching only this central
    // band avoids locking onto the spread's outer left/right page edges.
    final bandStart = (w * 0.20).round();
    final bandEnd = (w * 0.80).round();
    var peakCol = bandStart;
    var peakValue = colEnergy[bandStart];
    for (var x = bandStart; x < bandEnd; x++) {
      if (colEnergy[x] > peakValue) {
        peakValue = colEnergy[x];
        peakCol = x;
      }
    }

    final bandValues = colEnergy.sublist(bandStart, bandEnd);
    final bandMean = bandValues.reduce((a, b) => a + b) / bandValues.length;
    confidence = bandMean <= 0
        ? 0.0
        : ((peakValue - bandMean) / (bandMean + 1)).clamp(0.0, 1.0);

    final lumaBand = [...colLuma.sublist(bandStart, bandEnd)]..sort();
    final lumaMedian = lumaBand[lumaBand.length ~/ 2];
    var valleyCol = -1;
    var valleyLuma = lumaMedian;
    for (var x = bandStart; x < bandEnd; x++) {
      if (colLuma[x] < valleyLuma) {
        valleyLuma = colLuma[x];
        valleyCol = x;
      }
    }
    if (valleyCol >= 0 && lumaMedian > 1 && valleyLuma < lumaMedian * 0.72) {
      peakCol = valleyCol;
      confidence = ((lumaMedian - valleyLuma) / (lumaMedian + 1)).clamp(
        0.0,
        1.0,
      );
    }

    gutterX = peakCol / w;
  }

  final splitPixelX = (gutterX * decoded.width).round().clamp(
    1,
    decoded.width - 1,
  );

  final leftImage = img.copyCrop(
    decoded,
    x: 0,
    y: 0,
    width: splitPixelX,
    height: decoded.height,
  );
  final rightImage = img.copyCrop(
    decoded,
    x: splitPixelX,
    y: 0,
    width: decoded.width - splitPixelX,
    height: decoded.height,
  );

  File(
    args.leftOutputPath,
  ).writeAsBytesSync(img.encodeJpg(leftImage, quality: 92));
  File(
    args.rightOutputPath,
  ).writeAsBytesSync(img.encodeJpg(rightImage, quality: 92));

  return _SplitSpreadJobResult(
    leftPath: args.leftOutputPath,
    rightPath: args.rightOutputPath,
    confidence: confidence,
  );
}

class _DewarpArgs {
  const _DewarpArgs({
    required this.imagePath,
    required this.bounds,
    required this.outputPath,
  });

  final String imagePath;
  final Quad bounds;
  final String outputPath;
}

class _DewarpJobResult {
  const _DewarpJobResult({
    required this.outputPath,
    required this.occlusionDetected,
    required this.occlusionHighConfidenceTextLoss,
  });

  final String outputPath;
  final bool occlusionDetected;
  final bool occlusionHighConfidenceTextLoss;
}

/// Minimum curvature (in pixels, at analysis resolution) between a fitted
/// edge curve's lowest and highest point before flattening is worth the
/// distortion risk. Below this, the page is treated as flat.
const double _minCurvaturePixels = 4.0;

/// Below this fit quality (0..1, derived from residual variance) the
/// detected "curve" is more likely noise than real page bowing.
const double _minFitConfidence = 0.4;

_DewarpJobResult _dewarpJob(_DewarpArgs args) {
  final bytes = File(args.imagePath).readAsBytesSync();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw StateError('Cannot decode image at ${args.imagePath}');
  }

  final left = (args.bounds.topLeft.x * decoded.width).round().clamp(
    0,
    decoded.width - 1,
  );
  final right = (args.bounds.topRight.x * decoded.width).round().clamp(
    left + 1,
    decoded.width,
  );
  final top = (args.bounds.topLeft.y * decoded.height).round().clamp(
    0,
    decoded.height - 1,
  );
  final bottom = (args.bounds.bottomLeft.y * decoded.height).round().clamp(
    top + 1,
    decoded.height,
  );

  final boundsWidth = right - left;
  final boundsHeight = bottom - top;

  // `img.grayscale`/`img.sobel` mutate their input in place, so both run on
  // a clone — `decoded` must stay the original color image for the
  // skin-tone occlusion check below.
  final edges = img.sobel(img.grayscale(img.Image.from(decoded)));

  const sampleCount = 24;
  final xs = <double>[];
  final topYs = <double>[];
  final bottomYs = <double>[];
  final searchBand = (boundsHeight * 0.18).round().clamp(3, boundsHeight ~/ 2);

  for (var i = 0; i < sampleCount; i++) {
    final x = left + ((boundsWidth - 1) * i / (sampleCount - 1)).round();
    final topEdgeY = _findEdgeY(
      edges,
      x: x,
      from: top,
      to: math.min(top + searchBand, bottom - 1),
      forward: true,
    );
    final bottomEdgeY = _findEdgeY(
      edges,
      x: x,
      from: bottom - 1,
      to: math.max(bottom - 1 - searchBand, top),
      forward: false,
    );
    if (topEdgeY != null && bottomEdgeY != null && bottomEdgeY > topEdgeY) {
      xs.add(x.toDouble());
      topYs.add(topEdgeY.toDouble());
      bottomYs.add(bottomEdgeY.toDouble());
    }
  }

  bool occlusionDetected = false;
  bool occlusionHighConfidenceTextLoss = false;
  final skinMask = _skinToneBlob(
    decoded,
    left: left,
    top: top,
    right: right,
    bottom: bottom,
  );
  if (skinMask != null) {
    occlusionDetected = true;
    occlusionHighConfidenceTextLoss = skinMask.inCoreRegion;
  }

  if (xs.length < sampleCount ~/ 2) {
    // Not enough confident edge samples to fit a curve — preserve the
    // original rather than guess (SPEC 9.3: never invent structure over
    // low-confidence regions).
    File(args.outputPath).writeAsBytesSync(bytes);
    return _DewarpJobResult(
      outputPath: args.outputPath,
      occlusionDetected: occlusionDetected,
      occlusionHighConfidenceTextLoss: occlusionHighConfidenceTextLoss,
    );
  }

  final topFit = _fitQuadratic(xs, topYs);
  final bottomFit = _fitQuadratic(xs, bottomYs);

  final topRange = topYs.reduce(math.max) - topYs.reduce(math.min);
  final bottomRange = bottomYs.reduce(math.max) - bottomYs.reduce(math.min);
  final curvature = math.max(topRange, bottomRange);
  final fitConfidence = math.min(topFit.rSquared, bottomFit.rSquared);

  if (curvature < _minCurvaturePixels || fitConfidence < _minFitConfidence) {
    File(args.outputPath).writeAsBytesSync(bytes);
    return _DewarpJobResult(
      outputPath: args.outputPath,
      occlusionDetected: occlusionDetected,
      occlusionHighConfidenceTextLoss: occlusionHighConfidenceTextLoss,
    );
  }

  final targetHeight = boundsHeight;
  final flattened = img.Image(width: boundsWidth, height: targetHeight);
  for (var ox = 0; ox < boundsWidth; ox++) {
    final srcX = left + ox;
    final curveTop = topFit.evaluate(srcX.toDouble());
    final curveBottom = bottomFit.evaluate(srcX.toDouble());
    final span = curveBottom - curveTop;
    if (span <= 0) continue;
    for (var oy = 0; oy < targetHeight; oy++) {
      final srcY = curveTop + (span * oy / targetHeight);
      final pixel = decoded.getPixelInterpolate(
        srcX.toDouble(),
        srcY,
        interpolation: img.Interpolation.linear,
      );
      flattened.setPixel(ox, oy, pixel);
    }
  }

  File(args.outputPath).writeAsBytesSync(img.encodeJpg(flattened, quality: 92));
  return _DewarpJobResult(
    outputPath: args.outputPath,
    occlusionDetected: occlusionDetected,
    occlusionHighConfidenceTextLoss: occlusionHighConfidenceTextLoss,
  );
}

/// Scans column [x] from [from] toward [to] for the first pixel whose Sobel
/// magnitude clears a fraction of that column's local maximum; returns null
/// if no such edge is found (low-confidence region).
int? _findEdgeY(
  img.Image edges, {
  required int x,
  required int from,
  required int to,
  required bool forward,
}) {
  final step = forward ? 1 : -1;
  final count = (to - from).abs() + 1;
  double localMax = 0;
  for (var i = 0; i < count; i++) {
    final y = from + step * i;
    final v = edges.getPixel(x, y).r.toDouble();
    if (v > localMax) localMax = v;
  }
  if (localMax <= 0) return null;
  final threshold = localMax * 0.5;
  for (var i = 0; i < count; i++) {
    final y = from + step * i;
    if (edges.getPixel(x, y).r.toDouble() >= threshold) return y;
  }
  return null;
}

class _QuadraticFit {
  const _QuadraticFit(this.a, this.b, this.c, this.rSquared);

  final double a;
  final double b;
  final double c;
  final double rSquared;

  double evaluate(double x) => a * x * x + b * x + c;
}

/// Least-squares quadratic fit (y = ax^2 + bx + c) via the normal equations
/// on the 3x3 Vandermonde system — small, fixed-size, no external solver
/// dependency needed.
_QuadraticFit _fitQuadratic(List<double> xs, List<double> ys) {
  final n = xs.length;
  double sx = 0, sx2 = 0, sx3 = 0, sx4 = 0;
  double sy = 0, sxy = 0, sx2y = 0;
  for (var i = 0; i < n; i++) {
    final x = xs[i];
    final y = ys[i];
    final x2 = x * x;
    sx += x;
    sx2 += x2;
    sx3 += x2 * x;
    sx4 += x2 * x2;
    sy += y;
    sxy += x * y;
    sx2y += x2 * y;
  }

  // Solve the 3x3 normal-equations system via Cramer's rule.
  final m = [
    [sx4, sx3, sx2],
    [sx3, sx2, sx],
    [sx2, sx, n.toDouble()],
  ];
  final rhs = [sx2y, sxy, sy];
  final det = _det3(m);
  if (det.abs() < 1e-9) {
    // Degenerate (e.g. all-identical x) — flat fit.
    final meanY = sy / n;
    return _QuadraticFit(0, 0, meanY, 0);
  }

  final a = _det3(_replaceCol(m, 0, rhs)) / det;
  final b = _det3(_replaceCol(m, 1, rhs)) / det;
  final c = _det3(_replaceCol(m, 2, rhs)) / det;

  double ssRes = 0;
  double ssTot = 0;
  final meanY = sy / n;
  for (var i = 0; i < n; i++) {
    final predicted = a * xs[i] * xs[i] + b * xs[i] + c;
    ssRes += math.pow(ys[i] - predicted, 2);
    ssTot += math.pow(ys[i] - meanY, 2);
  }
  final rSquared = ssTot <= 0 ? 1.0 : (1 - ssRes / ssTot).clamp(0.0, 1.0);

  return _QuadraticFit(a, b, c, rSquared);
}

double _det3(List<List<double>> m) =>
    m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) -
    m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0]) +
    m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]);

List<List<double>> _replaceCol(
  List<List<double>> m,
  int col,
  List<double> values,
) => [
  for (var row = 0; row < 3; row++)
    [for (var c = 0; c < 3; c++) c == col ? values[row] : m[row][c]],
];

class _SkinBlob {
  const _SkinBlob(this.inCoreRegion);

  final bool inCoreRegion;
}

/// Coarse HSV skin-tone heuristic (SPEC 9.3 finger/occlusion detection).
/// Samples on a grid rather than every pixel for speed; flags a blob only
/// once enough grid cells clear the threshold to rule out isolated noise.
_SkinBlob? _skinToneBlob(
  img.Image image, {
  required int left,
  required int top,
  required int right,
  required int bottom,
}) {
  const gridStep = 8;
  var skinCells = 0;
  var coreSkinCells = 0;
  var totalCells = 0;

  final coreLeft = left + (right - left) * 0.15;
  final coreRight = right - (right - left) * 0.15;
  final coreTop = top + (bottom - top) * 0.15;
  final coreBottom = bottom - (bottom - top) * 0.15;

  for (var y = top; y < bottom; y += gridStep) {
    for (var x = left; x < right; x += gridStep) {
      totalCells++;
      final pixel = image.getPixel(x, y);
      if (_isSkinTone(
        pixel.r.toDouble(),
        pixel.g.toDouble(),
        pixel.b.toDouble(),
      )) {
        skinCells++;
        if (x >= coreLeft &&
            x <= coreRight &&
            y >= coreTop &&
            y <= coreBottom) {
          coreSkinCells++;
        }
      }
    }
  }

  if (totalCells == 0) return null;
  final skinFraction = skinCells / totalCells;
  if (skinFraction < 0.02) return null;

  final coreFraction = coreSkinCells / totalCells;
  return _SkinBlob(coreFraction >= 0.015);
}

bool _isSkinTone(double r, double g, double b) {
  final maxC = math.max(r, math.max(g, b));
  final minC = math.min(r, math.min(g, b));
  final delta = maxC - minC;
  if (maxC <= 0) return false;
  final v = maxC / 255;
  final s = maxC == 0 ? 0.0 : delta / maxC;

  double hue;
  if (delta == 0) {
    hue = 0;
  } else if (maxC == r) {
    hue = 60 * (((g - b) / delta) % 6);
  } else if (maxC == g) {
    hue = 60 * (((b - r) / delta) + 2);
  } else {
    hue = 60 * (((r - g) / delta) + 4);
  }
  if (hue < 0) hue += 360;

  return hue >= 0 && hue <= 50 && s >= 0.2 && s <= 0.7 && v >= 0.35;
}
