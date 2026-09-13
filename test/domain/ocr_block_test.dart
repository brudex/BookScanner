import 'package:bookscanner/domain/models/geometry.dart';
import 'package:bookscanner/domain/models/ocr_block.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  OcrBlock buildBlock() => const OcrBlock(
    id: 'b1',
    pageId: 'p1',
    boundingPolygon: Polygon([
      Point2D(x: 0.1, y: 0.1),
      Point2D(x: 0.5, y: 0.1),
      Point2D(x: 0.5, y: 0.2),
      Point2D(x: 0.1, y: 0.2),
    ]),
    text: 'Teh cat sat',
    confidence: 0.4,
    language: 'en',
    blockType: BlockType.paragraph,
    readingOrder: 0,
  );

  test('isLowConfidence true below threshold', () {
    expect(buildBlock().isLowConfidence, isTrue);
  });

  test('withCorrection appends history and raises confidence to 1.0', () {
    final block = buildBlock();
    final corrected = block.withCorrection('The cat sat', 1000);

    expect(corrected.text, 'The cat sat');
    expect(corrected.confidence, 1.0);
    expect(corrected.corrections, hasLength(1));
    expect(corrected.corrections.single.previousText, 'Teh cat sat');
    expect(corrected.wasCorrected, isTrue);
    // Original block instance is untouched (immutability).
    expect(block.text, 'Teh cat sat');
    expect(block.wasCorrected, isFalse);
  });
}
