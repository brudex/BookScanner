import 'package:bookscanner/ui/features/capture/preview_layout.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('letterboxes a 4:3 preview inside a tall parent without stretching', () {
    const parent = Size(300, 800);
    final rect = fittedPreviewRect(parent, 4 / 3);
    expect(rect.width / rect.height, closeTo(4 / 3, 0.001));
    expect(rect.height, 300 / (4 / 3));
    expect(rect.top, greaterThan(0));
    expect(rect.left, 0);
  });

  test('letterboxes a 4:3 preview inside a wide parent', () {
    const parent = Size(800, 300);
    final rect = fittedPreviewRect(parent, 4 / 3);
    expect(rect.width / rect.height, closeTo(4 / 3, 0.001));
    expect(rect.left, greaterThan(0));
    expect(rect.top, 0);
  });

  test('tap in letterbox is ignored; tap inside preview is normalized', () {
    const parent = Size(300, 800);
    final miss = previewNormalizedPoint(parent, 4 / 3, const Offset(10, 10));
    expect(miss, isNull);
    final rect = fittedPreviewRect(parent, 4 / 3);
    final hit = previewNormalizedPoint(parent, 4 / 3, rect.center);
    expect(hit, isNotNull);
    expect(hit!.dx, closeTo(0.5, 0.02));
    expect(hit.dy, closeTo(0.5, 0.02));
  });

  test('rotateNormalized covers 0/90/180/270', () {
    const p = Offset(0.25, 0.10);
    expect(rotateNormalized(p, 0), p);
    expect(rotateNormalized(p, 90), const Offset(0.90, 0.25));
    expect(rotateNormalized(p, 180), const Offset(0.75, 0.90));
    expect(rotateNormalized(p, 270), const Offset(0.10, 0.75));
  });
}
