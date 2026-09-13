import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../../../domain/models/geometry.dart';
import '../../../../domain/models/provider_info.dart';
import '../../../../domain/models/scan_page.dart';
import '../../../../domain/providers/image_enhancement_provider.dart';
import '../../local/file_storage_service.dart';
import '../page_detection.dart';

/// Cross-platform baseline enhancement adapter implemented in pure Dart on
/// top of `package:image`. Performs real perspective correction (quad
/// rectify), rotation, filter application, brightness/contrast/sharpness
/// adjustment, and shadow flattening via illumination-normalization — not a
/// placeholder. A native OpenCV/Core Image/RenderScript adapter can replace
/// this behind the same [ImageEnhancementProvider] contract without any
/// Flutter-side change (SPEC 9.3, 9.7) once built; this remains a valid
/// production default in the meantime because it produces genuinely
/// processed output rather than faking a result.
///
/// The actual pixel work runs on a background isolate via [compute] (SPEC
/// 11: "Camera preview and capture controls remain responsive during
/// background processing") — decode/rectify/blur/encode on a 4000x3000+
/// still is heavy enough to freeze the UI thread and trigger an ANR if run
/// inline, which is exactly what happened during on-device verification of
/// a multi-page capture burst before this was fixed.
class DartImageEnhancementProvider implements ImageEnhancementProvider {
  DartImageEnhancementProvider(this._fileStorage);

  final FileStorageService _fileStorage;

  @override
  ProviderInfo get info => const ProviderInfo(
    providerName: 'dart-image-baseline',
    adapterVersion: '1.2.0',
  );

  @override
  Future<double> scoreQuality(String imagePath) =>
      compute(_scoreQualityJob, imagePath);

  @override
  Future<EnhancementResult> enhance(EnhancementRequest request) async {
    final pageId = p.basenameWithoutExtension(request.outputImagePath);
    final thumbnailPath = _fileStorage.paths.thumbnailPathFor(pageId);

    final job = _EnhancementJob(
      sourceImagePath: request.sourceImagePath,
      outputImagePath: request.outputImagePath,
      thumbnailPath: thumbnailPath,
      cropPoints: request.cropPoints,
      rotationDegrees: request.rotationDegrees,
      filter: request.filter,
      brightness: request.brightness,
      contrast: request.contrast,
      sharpness: request.sharpness,
      removeShadowsAndStains: request.removeShadowsAndStains,
      detectCrop: request.detectCrop,
      splitOpenBook: request.splitOpenBook,
    );

    final result = await compute(_runEnhancementJob, job);
    return EnhancementResult(
      processedImagePath: request.outputImagePath,
      thumbnailPath: thumbnailPath,
      qualityScore: result.qualityScore,
      providerInfo: info,
      cropPoints: result.cropPoints,
    );
  }
}

double _scoreQualityJob(String imagePath) {
  final bytes = File(imagePath).readAsBytesSync();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return 0;
  return _estimateSharpness(decoded);
}

class _EnhancementJob {
  const _EnhancementJob({
    required this.sourceImagePath,
    required this.outputImagePath,
    required this.thumbnailPath,
    required this.cropPoints,
    required this.rotationDegrees,
    required this.filter,
    required this.brightness,
    required this.contrast,
    required this.sharpness,
    required this.removeShadowsAndStains,
    required this.detectCrop,
    required this.splitOpenBook,
  });

  final String sourceImagePath;
  final String outputImagePath;
  final String thumbnailPath;
  final Quad cropPoints;
  final int rotationDegrees;
  final PageFilter filter;
  final double brightness;
  final double contrast;
  final double sharpness;
  final bool removeShadowsAndStains;
  final bool detectCrop;
  final bool splitOpenBook;
}

class _EnhancementJobResult {
  const _EnhancementJobResult({
    required this.qualityScore,
    required this.cropPoints,
  });

  final double qualityScore;
  final Quad cropPoints;
}

const int _thumbnailMaxDimension = 320;

/// Top-level so it can run on a background isolate via [compute]. Mirrors
/// the pipeline previously inlined in [DartImageEnhancementProvider.enhance].
_EnhancementJobResult _runEnhancementJob(_EnhancementJob job) {
  final bytes = File(job.sourceImagePath).readAsBytesSync();
  var decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw StateError('Cannot decode image at ${job.sourceImagePath}');
  }

  decoded = img.bakeOrientation(decoded);

  var crop = job.cropPoints;
  if (crop == Quad.captureGuide) {
    crop = Quad.fullFrame;
  }
  if (job.detectCrop) {
    crop =
        detectDocumentQuad(decoded, splitOpenBook: job.splitOpenBook) ??
        (job.cropPoints == Quad.captureGuide ? Quad.fullFrame : job.cropPoints);
  }

  final cropped = crop != Quad.fullFrame;
  if (cropped) {
    decoded = _rectify(decoded, crop);
  }

  if (job.rotationDegrees != 0) {
    decoded = img.copyRotate(decoded, angle: job.rotationDegrees);
  }

  // Flattening walks every pixel of the still in Dart. On a missed crop
  // that's a full ~12MP photo and the slowest path; skip it unless we
  // actually isolated a page.
  if (cropped && job.removeShadowsAndStains) {
    decoded = _flattenIllumination(decoded);
    decoded = img.gaussianBlur(decoded, radius: 1);
  }

  decoded = _applyFilter(decoded, job.filter);

  if (job.brightness != 0 || job.contrast != 0) {
    decoded = img.adjustColor(
      decoded,
      brightness: 1.0 + (job.brightness.clamp(-100, 100) / 100),
      contrast: 1.0 + (job.contrast.clamp(-100, 100) / 100),
    );
  }

  if (job.sharpness > 0) {
    decoded = img.convolution(
      decoded,
      filter: [
        0,
        -1,
        0,
        -1,
        5 + job.sharpness.clamp(0, 100) / 25,
        -1,
        0,
        -1,
        0,
      ],
    );
  } else if (cropped) {
    decoded = img.convolution(
      decoded,
      filter: const [0, -0.5, 0, -0.5, 3, -0.5, 0, -0.5, 0],
    );
  }

  File(
    job.outputImagePath,
  ).writeAsBytesSync(img.encodeJpg(decoded, quality: 92));

  final thumbnail = img.copyResize(
    decoded,
    width: decoded.width >= decoded.height ? _thumbnailMaxDimension : null,
    height: decoded.height > decoded.width ? _thumbnailMaxDimension : null,
  );
  File(
    job.thumbnailPath,
  ).writeAsBytesSync(img.encodeJpg(thumbnail, quality: 80));

  final quality = _estimateSharpness(decoded);
  return _EnhancementJobResult(qualityScore: quality, cropPoints: crop);
}

double _estimateSharpness(img.Image image) {
  final gray = img.grayscale(image, amount: 1);
  final sample = img.copyResize(gray, width: math.min(600, gray.width));
  double variance = 0;
  double mean = 0;
  var count = 0;
  for (var y = 1; y < sample.height - 1; y += 2) {
    for (var x = 1; x < sample.width - 1; x += 2) {
      final c = sample.getPixel(x, y).r;
      final l = sample.getPixel(x - 1, y).r;
      final r = sample.getPixel(x + 1, y).r;
      final t = sample.getPixel(x, y - 1).r;
      final b = sample.getPixel(x, y + 1).r;
      final laplacian = (4 * c - l - r - t - b).toDouble();
      mean += laplacian;
      count++;
    }
  }
  if (count == 0) return 0.5;
  mean /= count;
  for (var y = 1; y < sample.height - 1; y += 2) {
    for (var x = 1; x < sample.width - 1; x += 2) {
      final c = sample.getPixel(x, y).r;
      final l = sample.getPixel(x - 1, y).r;
      final r = sample.getPixel(x + 1, y).r;
      final t = sample.getPixel(x, y - 1).r;
      final b = sample.getPixel(x, y + 1).r;
      final laplacian = (4 * c - l - r - t - b).toDouble();
      variance += (laplacian - mean) * (laplacian - mean);
    }
  }
  variance /= count;
  // Empirically-scaled: variance of Laplacian is a standard blur proxy.
  // Higher variance = sharper. Clamp to 0..1.
  return (variance / 900).clamp(0.0, 1.0);
}

img.Image _rectify(img.Image src, Quad quad) {
  final w = src.width.toDouble();
  final h = src.height.toDouble();
  final topLeft = img.Point(quad.topLeft.x * w, quad.topLeft.y * h);
  final topRight = img.Point(quad.topRight.x * w, quad.topRight.y * h);
  final bottomLeft = img.Point(quad.bottomLeft.x * w, quad.bottomLeft.y * h);
  final bottomRight = img.Point(quad.bottomRight.x * w, quad.bottomRight.y * h);

  // `copyRectify` maps the given quad onto its `toImage` destination --
  // left unspecified, it defaults to a plain copy of `src`'s own
  // dimensions, which stretches the cropped content to fit whatever aspect
  // ratio the *source photo* happened to have, distorting the document
  // whenever the selected quad's own shape doesn't match that (e.g. a
  // portrait book page cropped out of a landscape-oriented capture). Size
  // the destination to the quad's own average edge lengths instead, so the
  // output preserves the document's actual proportions.
  final outWidth =
      ((_distance(topLeft, topRight) + _distance(bottomLeft, bottomRight)) / 2)
          .round()
          .clamp(1, 1 << 16);
  final outHeight =
      ((_distance(topLeft, bottomLeft) + _distance(topRight, bottomRight)) / 2)
          .round()
          .clamp(1, 1 << 16);

  return img.copyRectify(
    src,
    topLeft: topLeft,
    topRight: topRight,
    bottomLeft: bottomLeft,
    bottomRight: bottomRight,
    interpolation: img.Interpolation.linear,
    toImage: img.Image(width: outWidth, height: outHeight),
  );
}

double _distance(img.Point a, img.Point b) {
  final dx = a.x - b.x;
  final dy = a.y - b.y;
  return math.sqrt(dx * dx + dy * dy);
}

/// Removes soft shadows/uneven lighting without erasing text: divides the
/// image by a heavily-blurred copy of itself (background-illumination
/// estimate) and rescales, a standard document-scanning technique.
///
/// The blur runs on a small downscaled copy, not the full-resolution image:
/// background illumination is inherently low-frequency (shadows/gradients
/// vary smoothly across a page), so a small blurred copy upscaled back
/// gives a visually equivalent estimate. Blurring at full resolution here
/// was the single largest cost in the whole per-capture pipeline -- a
/// `radius: 25` Gaussian blur over a real ~12MP photo, observed on-device
/// as "capture takes too long," easily dwarfing everything else this
/// function or the rest of the enhancement pipeline does.
img.Image _flattenIllumination(img.Image src) {
  const downscaleWidth = 300;
  final scale = downscaleWidth / src.width;
  final small = img.copyResize(
    src,
    width: downscaleWidth,
    height: (src.height * scale).round().clamp(1, src.height),
  );
  final blurredSmall = img.gaussianBlur(small, radius: 12);
  final background = img.copyResize(
    blurredSmall,
    width: src.width,
    height: src.height,
    interpolation: img.Interpolation.linear,
  );
  final out = img.Image.from(src);
  for (var y = 0; y < out.height; y++) {
    for (var x = 0; x < out.width; x++) {
      final p = src.getPixel(x, y);
      final bg = background.getPixel(x, y);
      final nr = _normalizeChannel(p.r.toDouble(), bg.r.toDouble());
      final ng = _normalizeChannel(p.g.toDouble(), bg.g.toDouble());
      final nb = _normalizeChannel(p.b.toDouble(), bg.b.toDouble());
      out.setPixelRgb(x, y, nr, ng, nb);
    }
  }
  return out;
}

double _normalizeChannel(double value, double background) {
  if (background <= 1) return value;
  final normalized = (value / background) * 235;
  return normalized.clamp(0, 255);
}

img.Image _applyFilter(img.Image src, PageFilter filter) => switch (filter) {
  PageFilter.original => src,
  PageFilter.enhancedColor => img.adjustColor(
    src,
    contrast: 1.18,
    saturation: 1.12,
    brightness: 1.02,
  ),
  PageFilter.grayscale => img.grayscale(src),
  PageFilter.blackAndWhite => _adaptiveThreshold(src),
  PageFilter.photo => img.adjustColor(
    src,
    contrast: 1.05,
    saturation: 1.05,
    brightness: 1.02,
  ),
};

img.Image _adaptiveThreshold(img.Image src) {
  final gray = img.grayscale(src);
  const block = 15;
  const c = 8;
  final w = gray.width;
  final h = gray.height;
  final integral = List<int>.filled((w + 1) * (h + 1), 0);
  for (var y = 1; y <= h; y++) {
    var row = 0;
    for (var x = 1; x <= w; x++) {
      row += gray.getPixel(x - 1, y - 1).r.toInt();
      integral[y * (w + 1) + x] = integral[(y - 1) * (w + 1) + x] + row;
    }
  }
  int sumRect(int x0, int y0, int x1, int y1) {
    return integral[y1 * (w + 1) + x1] -
        integral[y0 * (w + 1) + x1] -
        integral[y1 * (w + 1) + x0] +
        integral[y0 * (w + 1) + x0];
  }

  final half = block ~/ 2;
  final out = img.Image.from(gray);
  for (var y = 0; y < h; y++) {
    final y0 = (y - half).clamp(0, h - 1);
    final y1 = (y + half).clamp(0, h - 1) + 1;
    for (var x = 0; x < w; x++) {
      final x0 = (x - half).clamp(0, w - 1);
      final x1 = (x + half).clamp(0, w - 1) + 1;
      final area = (x1 - x0) * (y1 - y0);
      final mean = area == 0 ? 128 : sumRect(x0, y0, x1, y1) / area;
      final v = gray.getPixel(x, y).r > mean - c ? 255 : 0;
      out.setPixelRgb(x, y, v, v, v);
    }
  }
  return out;
}
