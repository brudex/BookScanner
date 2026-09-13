// Not a test file (no `_test.dart` suffix, matching test/data/fakes/'s
// convention for shared non-test helpers).
//
// The "consented test corpus" SPEC.md requires (line 385): "Build a
// consented test corpus covering flat pages, curved books, glossy paper,
// shadows, fingers, skew, low light, multi-column layouts, tables,
// illustrations, and right-to-left text." Since this environment has no
// real scanned photos to consent and include, every fixture here is
// synthetic -- built with package:image using the same drawing primitives
// (fill/fillRect/fillPolygon/gaussianBlur/setPixel) every other test file in
// this codebase already uses, rather than real photographic fixtures.
//
// Each function is documented with exactly which real-world condition it
// approximates and, where relevant, which pipeline-stage behavior it's
// meant to exercise -- see pipeline_corpus_test.dart, the suite built on
// top of this file.

import 'dart:io';
import 'dart:math' as math;

import 'package:bookscanner/domain/models/geometry.dart';
import 'package:bookscanner/domain/models/ocr_block.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// Writes [image] as a JPEG under [dir] and returns its path. Shared by
/// every image-based corpus builder below.
String writeCorpusImage(Directory dir, img.Image image, String name) {
  final path = p.join(dir.path, name);
  File(path).writeAsBytesSync(img.encodeJpg(image, quality: 95));
  return path;
}

/// 1. "Flat page" -- a bright, evenly-lit rectangular page against a dark
/// background, with fine repeating detail (a small-tile checkerboard)
/// standing in for real printed text. Exercises page detection (should find
/// the page's axis-aligned bounds) and quality scoring (should score high,
/// since the checkerboard gives the sharpness metric plenty of local
/// contrast).
String flatPage(Directory dir) {
  const size = 400;
  final image = img.Image(width: size, height: size);
  img.fill(image, color: img.ColorRgb8(30, 30, 30));
  for (var y = 40; y < 360; y++) {
    for (var x = 60; x < 340; x++) {
      final isLight = ((x ~/ 4) + (y ~/ 4)).isEven;
      final v = isLight ? 240 : 20;
      image.setPixelRgb(x, y, v, v, v);
    }
  }
  return writeCorpusImage(dir, image, 'flat_page.jpg');
}

/// 2a. "Curved book" (spread) -- a two-page spread photo with a clear
/// vertical gutter shadow at the spine, inside the 35%-65% search band
/// `BookDewarpProvider.splitSpread` scans. Exercises spread splitting.
String curvedBookSpread(Directory dir) {
  const width = 500;
  const height = 350;
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(235, 235, 235));
  img.fillRect(
    image,
    x1: (width * 0.49).round(),
    y1: 0,
    x2: (width * 0.51).round(),
    y2: height - 1,
    color: img.ColorRgb8(20, 20, 20),
  );
  return writeCorpusImage(dir, image, 'curved_book_spread.jpg');
}

/// 2b. "Curved book" (single already-split page) -- top/bottom edges follow
/// a parabola (the page bowing away from the spine) with amplitude well
/// past `DartBookDewarpProvider`'s 4px flatness floor. Exercises curvature
/// flattening (`dewarp`).
String curvedBookPage(Directory dir) {
  const width = 300;
  const height = 400;
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  for (var x = 0; x < width; x++) {
    final top = 50 + (0.001 * math.pow(x - 150, 2)).round();
    final bottom = 350 - (0.001 * math.pow(x - 150, 2)).round();
    for (var y = top; y <= bottom; y++) {
      image.setPixel(x, y, img.ColorRgb8(200, 200, 200));
    }
  }
  return writeCorpusImage(dir, image, 'curved_book_page.jpg');
}

/// The [Quad] page bounds paired with [curvedBookPage] / [flatLitPage] /
/// [fingerOcclusionCore] / [fingerOcclusionMargin] for `dewarp()` calls --
/// matches `dart_book_dewarp_provider_test.dart`'s bounds exactly (10%-95%
/// vertically, full width) so results are directly comparable to that
/// file's coverage.
const corpusPageBounds = Quad(
  topLeft: Point2D(x: 0, y: 0.1),
  topRight: Point2D(x: 1, y: 0.1),
  bottomRight: Point2D(x: 1, y: 0.95),
  bottomLeft: Point2D(x: 0, y: 0.95),
);

img.Image _flatLitPageImage() {
  final image = img.Image(width: 300, height: 400);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  img.fillRect(
    image,
    x1: 0,
    y1: 50,
    x2: 299,
    y2: 349,
    color: img.ColorRgb8(200, 200, 200),
  );
  return image;
}

/// 3. "Glossy paper" -- a page with real fine detail plus a large smooth,
/// saturated-bright patch simulating a flash/light reflection off glossy
/// stock. There is no dedicated glare-detection/compensation step in
/// `DartImageEnhancementProvider`; this fixture's role is to confirm that
/// gap doesn't manifest as a crash or a spuriously zeroed quality score.
String glossyPage(Directory dir) {
  const size = 300;
  final image = img.Image(width: size, height: size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final isLight = ((x ~/ 4) + (y ~/ 4)).isEven;
      final v = isLight ? 240 : 20;
      image.setPixelRgb(x, y, v, v, v);
    }
  }
  img.fillRect(
    image,
    x1: 150,
    y1: 0,
    x2: 299,
    y2: 149,
    color: img.ColorRgb8(255, 255, 255),
  );
  return writeCorpusImage(dir, image, 'glossy_page.jpg');
}

/// 4. "Shadows" -- a smooth horizontal luminance ramp across the page (a
/// soft shadow or uneven lighting would produce exactly this kind of low-
/// frequency gradient). Exercises `removeShadowsAndStains` illumination
/// normalization.
String shadowedPage(Directory dir) {
  const size = 300;
  final image = img.Image(width: size, height: size);
  for (var x = 0; x < size; x++) {
    final value = (220 - (120 * x / size)).round().clamp(0, 255);
    for (var y = 0; y < size; y++) {
      image.setPixelRgb(x, y, value, value, value);
    }
  }
  return writeCorpusImage(dir, image, 'shadowed_page.jpg');
}

/// 5a. "Fingers" -- a skin-toned patch over the *core* (central 70%) of the
/// page bounds. Exercises the HSV skin-tone occlusion heuristic's
/// high-confidence ("text loss, needs rescan") path.
String fingerOcclusionCore(Directory dir) {
  final image = _flatLitPageImage();
  img.fillRect(
    image,
    x1: 120,
    y1: 180,
    x2: 180,
    y2: 240,
    color: img.ColorRgb8(222, 170, 140),
  );
  return writeCorpusImage(dir, image, 'finger_occlusion_core.jpg');
}

/// 5b. "Fingers" -- the same skin tone, but confined to the outer 15%
/// margin band. Exercises the occlusion heuristic's warning-only (no
/// rescan) path.
String fingerOcclusionMargin(Directory dir) {
  final image = _flatLitPageImage();
  img.fillRect(
    image,
    x1: 0,
    y1: 50,
    x2: 20,
    y2: 349,
    color: img.ColorRgb8(222, 170, 140),
  );
  return writeCorpusImage(dir, image, 'finger_occlusion_margin.jpg');
}

/// 6. "Skew" -- a page rotated [angleDegrees] off-axis against a contrasting
/// background. Exercises page detection's contour+quad path (a tight rotated
/// fit, not an axis-aligned bounding box) and the downstream perspective
/// warp that removes the surrounding background.
String skewedPage(Directory dir, {double angleDegrees = 12}) {
  const size = 400;
  const halfWidth = 100.0;
  const halfHeight = 140.0;
  const centerX = 200.0;
  const centerY = 200.0;
  final angle = angleDegrees * math.pi / 180;
  final cosA = math.cos(angle);
  final sinA = math.sin(angle);
  img.Point rotated(double dx, double dy) => img.Point(
    centerX + dx * cosA - dy * sinA,
    centerY + dx * sinA + dy * cosA,
  );

  final image = img.Image(width: size, height: size);
  img.fill(image, color: img.ColorRgb8(30, 30, 30));
  img.fillPolygon(
    image,
    vertices: [
      rotated(-halfWidth, -halfHeight),
      rotated(halfWidth, -halfHeight),
      rotated(halfWidth, halfHeight),
      rotated(-halfWidth, halfHeight),
    ],
    color: img.ColorRgb8(245, 245, 245),
  );
  return writeCorpusImage(dir, image, 'skewed_page.jpg');
}

/// 7. "Low light" -- reduced sharpness (motion blur / sensor-noise
/// smoothing), which is what actually drives this provider's quality score
/// down; raw darkness alone does not (see
/// dart_image_enhancement_provider_test.dart's "darkening... does not by
/// itself lower the score" case). Modeled as a blurred checkerboard at
/// reduced luminance, which is what a real handheld low-light capture's
/// loss of detail looks like once downsampled.
String lowLightPage(Directory dir) {
  const size = 300;
  final sharp = img.Image(width: size, height: size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final isLight = ((x ~/ 4) + (y ~/ 4)).isEven;
      final v = isLight ? 90 : 20;
      sharp.setPixelRgb(x, y, v, v, v);
    }
  }
  final blurred = img.gaussianBlur(sharp, radius: 6);
  return writeCorpusImage(dir, blurred, 'low_light_page.jpg');
}

// --- OCR-layout corpus fixtures ------------------------------------------
//
// These four categories are fundamentally about reading-order/classification
// of already-recognized text, not raw pixels -- there's no OCR engine
// running in this test environment, so (matching
// analyze_ocr_layout_use_case_test.dart's existing convention) they're
// expressed directly as synthetic OcrBlock lists, as if OCR had already run.

OcrBlock _rawLine(
  String text, {
  required double top,
  required double bottom,
  double left = 0.1,
  double right = 0.9,
  double confidence = 0.9,
  int readingOrder = 0,
}) => OcrBlock(
  id: '',
  pageId: '',
  boundingPolygon: Polygon([
    Point2D(x: left, y: top),
    Point2D(x: right, y: top),
    Point2D(x: right, y: bottom),
    Point2D(x: left, y: bottom),
  ]),
  text: text,
  confidence: confidence,
  language: 'en',
  blockType: BlockType.unknown,
  readingOrder: readingOrder,
);

/// 8. "Multi-column layouts" -- two clean columns of body text, well clear
/// of the 0.45-0.55 centerX gutter band `AnalyzeOcrLayoutUseCase` requires
/// to detect a 2-column run.
List<OcrBlock> multiColumnLayoutRawLines() => [
  _rawLine(
    'Left column line one',
    top: 0.20,
    bottom: 0.23,
    left: 0.1,
    right: 0.4,
    readingOrder: 0,
  ),
  _rawLine(
    'Right column line one',
    top: 0.20,
    bottom: 0.23,
    left: 0.6,
    right: 0.9,
    readingOrder: 1,
  ),
  _rawLine(
    'Left column line two',
    top: 0.24,
    bottom: 0.27,
    left: 0.1,
    right: 0.4,
    readingOrder: 2,
  ),
  _rawLine(
    'Right column line two',
    top: 0.24,
    bottom: 0.27,
    left: 0.6,
    right: 0.9,
    readingOrder: 3,
  ),
];

/// 9. "Tables" -- a 2x3 grid of short cell-like lines. `BlockType.table`/
/// `tableCell` exist in the domain model but `AnalyzeOcrLayoutUseCase` never
/// assigns them (confirmed: no table-detection logic exists in that file at
/// all) -- this fixture exists to make that a checked, honest limitation
/// rather than an untested assumption.
List<OcrBlock> tableLayoutRawLines() => [
  _rawLine(
    'Name',
    top: 0.30,
    bottom: 0.33,
    left: 0.1,
    right: 0.3,
    readingOrder: 0,
  ),
  _rawLine(
    'Qty',
    top: 0.30,
    bottom: 0.33,
    left: 0.4,
    right: 0.5,
    readingOrder: 1,
  ),
  _rawLine(
    'Price',
    top: 0.30,
    bottom: 0.33,
    left: 0.6,
    right: 0.8,
    readingOrder: 2,
  ),
  _rawLine(
    'Widget',
    top: 0.35,
    bottom: 0.38,
    left: 0.1,
    right: 0.3,
    readingOrder: 3,
  ),
  _rawLine(
    '4',
    top: 0.35,
    bottom: 0.38,
    left: 0.4,
    right: 0.5,
    readingOrder: 4,
  ),
  _rawLine(
    '9.99',
    top: 0.35,
    bottom: 0.38,
    left: 0.6,
    right: 0.8,
    readingOrder: 5,
  ),
];

/// 10. "Illustrations" -- a picture-only page with no recognizable text at
/// all, i.e. OCR legitimately found zero lines.
List<OcrBlock> illustrationRawLines() => const [];

/// 11. "Right-to-left text" -- geometrically identical to the 2-column case
/// (2 lines per column, needed to actually trigger `_orderColumnRun`'s
/// `left.length >= 2 && right.length >= 2` two-column branch) but with
/// RTL-script content (Arabic), and critically with the *visually first*
/// (rightmost) column being the one a right-to-left reader would read
/// first. `AnalyzeOcrLayoutUseCase` has no script-direction awareness
/// anywhere (confirmed: `_orderColumnRun` always emits the left-centerX
/// bucket before the right-centerX bucket, regardless of content) -- this
/// fixture exists to make that a checked limitation, matching
/// IMPLEMENTATION_STATUS.md §5's note that page-order-direction is modeled
/// in metadata only and "not yet wired into any UI or export ordering
/// logic."
List<OcrBlock> rtlTextLayoutRawLines() => [
  _rawLine(
    'يجب قراءة هذا العمود أولاً', // "This column should be read first" (rightmost)
    top: 0.20,
    bottom: 0.23,
    left: 0.6,
    right: 0.9,
    readingOrder: 0,
  ),
  _rawLine(
    'ثم هذا السطر', // "then this line" (rightmost, second line)
    top: 0.24,
    bottom: 0.27,
    left: 0.6,
    right: 0.9,
    readingOrder: 1,
  ),
  _rawLine(
    'يجب قراءة هذا العمود ثانياً', // "This column should be read second" (leftmost)
    top: 0.20,
    bottom: 0.23,
    left: 0.1,
    right: 0.4,
    readingOrder: 2,
  ),
  _rawLine(
    'ثم هذا السطر أيضاً', // "then this line too" (leftmost, second line)
    top: 0.24,
    bottom: 0.27,
    left: 0.1,
    right: 0.4,
    readingOrder: 3,
  ),
];
