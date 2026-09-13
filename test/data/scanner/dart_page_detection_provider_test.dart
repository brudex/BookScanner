import 'dart:io';
import 'dart:math' as math;

import 'package:bookscanner/data/services/scanner/adapters/dart_page_detection_provider.dart';
import 'package:bookscanner/domain/models/geometry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

void main() {
  late Directory tmpDir;
  late DartPageDetectionProvider provider;

  setUpAll(() async {
    tmpDir = await Directory.systemTemp.createTemp('page_detection_test_');
  });

  setUp(() {
    provider = DartPageDetectionProvider();
  });

  tearDownAll(() async {
    if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
  });

  String writeImage(img.Image image, String name) {
    final path = p.join(tmpDir.path, name);
    File(path).writeAsBytesSync(img.encodeJpg(image, quality: 95));
    return path;
  }

  test(
    'detects a tight quad for a flat page with strong background contrast',
    () async {
      final image = img.Image(width: 400, height: 400);
      img.fill(image, color: img.ColorRgb8(30, 30, 30));
      img.fillRect(
        image,
        x1: 60,
        y1: 40,
        x2: 339,
        y2: 359,
        color: img.ColorRgb8(245, 245, 245),
      );
      final path = writeImage(image, 'flat_page.jpg');

      final quad = await provider.detectQuad(path);

      expect(quad, isNotNull);
      expect(quad!.topLeft.x, closeTo(60 / 400, 0.05));
      expect(quad.topRight.x, closeTo(339 / 400, 0.05));
      expect(quad.topLeft.y, closeTo(40 / 400, 0.05));
      expect(quad.bottomLeft.y, closeTo(359 / 400, 0.05));
    },
  );

  test(
    'returns null when the only edge signal is too small relative to the frame',
    () async {
      final image = img.Image(width: 400, height: 400);
      img.fill(image, color: img.ColorRgb8(30, 30, 30));
      img.fillRect(
        image,
        x1: 180,
        y1: 180,
        x2: 220,
        y2: 220,
        color: img.ColorRgb8(245, 245, 245),
      );
      final path = writeImage(image, 'too_small.jpg');

      final quad = await provider.detectQuad(path);

      expect(quad, isNull);
    },
  );

  test(
    'fits a rotated page tightly instead of its axis-aligned bounding box',
    () async {
      const halfWidth = 100.0;
      const halfHeight = 140.0;
      const angle = 12 * math.pi / 180;
      const centerX = 200.0;
      const centerY = 200.0;
      final cosA = math.cos(angle);
      final sinA = math.sin(angle);
      img.Point rotated(double dx, double dy) => img.Point(
        centerX + dx * cosA - dy * sinA,
        centerY + dx * sinA + dy * cosA,
      );

      final image = img.Image(width: 400, height: 400);
      img.fill(image, color: img.ColorRgb8(30, 30, 30));
      final vertices = [
        rotated(-halfWidth, -halfHeight),
        rotated(halfWidth, -halfHeight),
        rotated(halfWidth, halfHeight),
        rotated(-halfWidth, halfHeight),
      ];
      img.fillPolygon(
        image,
        vertices: vertices,
        color: img.ColorRgb8(245, 245, 245),
      );
      final path = writeImage(image, 'skewed_page.jpg');

      final quad = await provider.detectQuad(path);

      expect(quad, isNotNull);
      // A tight fit following the tilted edges is not axis-aligned.
      expect((quad!.topLeft.y - quad.topRight.y).abs(), greaterThan(0.04));

      Point2D expected(img.Point p) => Point2D(x: p.x / 400, y: p.y / 400);
      expect(quad.topLeft.x, closeTo(expected(vertices[0]).x, 0.06));
      expect(quad.topLeft.y, closeTo(expected(vertices[0]).y, 0.06));
      expect(quad.topRight.x, closeTo(expected(vertices[1]).x, 0.06));
      expect(quad.topRight.y, closeTo(expected(vertices[1]).y, 0.06));
      expect(quad.bottomRight.x, closeTo(expected(vertices[2]).x, 0.06));
      expect(quad.bottomRight.y, closeTo(expected(vertices[2]).y, 0.06));
      expect(quad.bottomLeft.x, closeTo(expected(vertices[3]).x, 0.06));
      expect(quad.bottomLeft.y, closeTo(expected(vertices[3]).y, 0.06));
    },
  );

  test(
    'fits a perspective trapezoid, not its axis-aligned bounding box',
    () async {
      // Wider at the bottom, as if the page was photographed from above.
      const tl = (120.0, 50.0);
      const tr = (280.0, 55.0);
      const br = (350.0, 350.0);
      const bl = (50.0, 345.0);

      final image = img.Image(width: 400, height: 400);
      img.fill(image, color: img.ColorRgb8(30, 30, 30));
      img.fillPolygon(
        image,
        vertices: [
          img.Point(tl.$1, tl.$2),
          img.Point(tr.$1, tr.$2),
          img.Point(br.$1, br.$2),
          img.Point(bl.$1, bl.$2),
        ],
        color: img.ColorRgb8(245, 245, 245),
      );
      final path = writeImage(image, 'trapezoid_page.jpg');

      final quad = await provider.detectQuad(path);

      expect(quad, isNotNull);
      expect(quad!.topLeft.x, closeTo(tl.$1 / 400, 0.06));
      expect(quad.topLeft.y, closeTo(tl.$2 / 400, 0.06));
      expect(quad.topRight.x, closeTo(tr.$1 / 400, 0.06));
      expect(quad.bottomRight.x, closeTo(br.$1 / 400, 0.06));
      expect(quad.bottomLeft.x, closeTo(bl.$1 / 400, 0.06));
      // Must not collapse to the AABB (x=50..350 on every row).
      expect(quad.topLeft.x, greaterThan(80 / 400));
      expect(quad.topRight.x, lessThan(320 / 400));
    },
  );

  test('does not crop into printed text on a text-heavy page', () async {
    // Regression for the on-device over-crop: interior text lines have
    // stronger Sobel energy than the paper-to-background edge, so a
    // projection-profile scan used to stop at the first line of text.
    final image = img.Image(width: 400, height: 400);
    img.fill(image, color: img.ColorRgb8(30, 30, 30));
    img.fillRect(
      image,
      x1: 50,
      y1: 40,
      x2: 350,
      y2: 360,
      color: img.ColorRgb8(245, 245, 245),
    );
    for (var i = 0; i < 16; i++) {
      final y = 80 + i * 16;
      img.drawLine(
        image,
        x1: 70,
        y1: y,
        x2: 330,
        y2: y,
        color: img.ColorRgb8(20, 20, 20),
        thickness: 3,
      );
    }
    final path = writeImage(image, 'text_heavy.jpg');

    final quad = await provider.detectQuad(path);

    expect(quad, isNotNull);
    expect(quad!.topLeft.y, closeTo(40 / 400, 0.06));
    expect(
      quad.topLeft.y,
      lessThan(70 / 400),
      reason: 'crop must stay at the paper edge, not the first text line',
    );
    expect(quad.bottomLeft.y, closeTo(360 / 400, 0.06));
  });

  test(
    'an open book framed on the right page crops that page, not a quad that cuts through it',
    () async {
      // Matches the on-device failure: both pages are one paper blob, so a
      // 4-corner fit of the whole book put a vertex on the gutter — in the
      // middle of the page the user actually framed.
      final image = img.Image(width: 400, height: 400);
      img.fill(image, color: img.ColorRgb8(40, 40, 40));
      img.fillPolygon(
        image,
        vertices: [
          img.Point(0, 50),
          img.Point(145, 55),
          img.Point(145, 350),
          img.Point(0, 360),
        ],
        color: img.ColorRgb8(235, 228, 210),
      );
      img.fillRect(
        image,
        x1: 145,
        y1: 40,
        x2: 158,
        y2: 360,
        color: img.ColorRgb8(50, 42, 32),
      );
      img.fillPolygon(
        image,
        vertices: [
          img.Point(158, 45),
          img.Point(385, 55),
          img.Point(370, 365),
          img.Point(158, 350),
        ],
        color: img.ColorRgb8(242, 236, 220),
      );
      img.fillRect(
        image,
        x1: 200,
        y1: 160,
        x2: 330,
        y2: 200,
        color: img.ColorRgb8(60, 60, 60),
      );
      final path = writeImage(image, 'open_book_right_page.jpg');

      final quad = await provider.detectQuad(path);

      expect(quad, isNotNull);
      expect(
        quad!.topLeft.x,
        greaterThan(0.28),
        reason: 'left edge should be the gutter, not the left-hand page',
      );
      expect(
        quad.topLeft.x,
        lessThan(0.50),
        reason: 'must not put a corner in the middle of the right-hand page',
      );
      expect(quad.topRight.x, greaterThan(0.85));
    },
  );

  test(
    'returns null for a full-bleed page with no surrounding background',
    () async {
      final image = img.Image(width: 400, height: 400);
      img.fill(image, color: img.ColorRgb8(250, 250, 248));
      for (var i = 0; i < 12; i++) {
        img.drawLine(
          image,
          x1: 40,
          y1: 40 + i * 28,
          x2: 360,
          y2: 40 + i * 28,
          color: img.ColorRgb8(30, 30, 30),
          thickness: 2,
        );
      }
      final path = writeImage(image, 'full_bleed.jpg');

      final quad = await provider.detectQuad(path);

      expect(quad, isNull);
    },
  );

  test(
    'returns null when paper is visible but is not a confident 4-corner page',
    () async {
      // An L-shaped bright region has a real paper/background split, but
      // the convex hull is not page-shaped. Uncertain detections must not
      // invent a crop from the static capture guide.
      final image = img.Image(width: 400, height: 400);
      img.fill(image, color: img.ColorRgb8(25, 25, 25));
      img.fillRect(
        image,
        x1: 40,
        y1: 40,
        x2: 280,
        y2: 110,
        color: img.ColorRgb8(240, 240, 240),
      );
      img.fillRect(
        image,
        x1: 40,
        y1: 40,
        x2: 110,
        y2: 300,
        color: img.ColorRgb8(240, 240, 240),
      );
      final path = writeImage(image, 'l_shape_paper.jpg');

      final quad = await provider.detectQuad(path);

      expect(quad, isNull);
    },
  );
}
