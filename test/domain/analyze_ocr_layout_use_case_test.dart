import 'package:bookscanner/domain/models/geometry.dart';
import 'package:bookscanner/domain/models/ocr_block.dart';
import 'package:bookscanner/domain/use_cases/analyze_ocr_layout_use_case.dart';
import 'package:flutter_test/flutter_test.dart';

OcrBlock rawLine(
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

void main() {
  late AnalyzeOcrLayoutUseCase useCase;

  setUp(() {
    useCase = AnalyzeOcrLayoutUseCase();
  });

  test('empty input returns empty output', () {
    expect(useCase('page1', []), isEmpty);
  });

  test(
    'classifies heading, merges wrapped paragraph lines, keeps list item and page number separate',
    () {
      final raw = [
        rawLine('Chapter One', top: 0.05, bottom: 0.11, readingOrder: 0),
        rawLine(
          'It was a dark and stormy night, and the old house',
          top: 0.18,
          bottom: 0.22,
          readingOrder: 1,
        ),
        rawLine(
          'creaked with every gust of wind.',
          top: 0.22,
          bottom: 0.26,
          readingOrder: 2,
        ),
        rawLine(
          '- First point of interest',
          top: 0.32,
          bottom: 0.36,
          readingOrder: 3,
        ),
        rawLine('12', top: 0.94, bottom: 0.97, readingOrder: 4),
      ];

      final result = useCase('page1', raw);

      expect(result, hasLength(4));
      expect(result[0].blockType, BlockType.heading);
      expect(result[0].text, 'Chapter One');
      expect(result[0].headingLevel, 1);

      expect(result[1].blockType, BlockType.paragraph);
      expect(
        result[1].text,
        'It was a dark and stormy night, and the old house creaked with every gust of wind.',
      );

      expect(result[2].blockType, BlockType.listItem);
      expect(result[3].blockType, BlockType.pageNumber);

      for (var i = 0; i < result.length; i++) {
        expect(result[i].readingOrder, i);
        expect(result[i].pageId, 'page1');
        expect(result[i].id, isNotEmpty);
      }
      // ids must be unique
      expect(result.map((b) => b.id).toSet(), hasLength(result.length));
    },
  );

  test('does not merge paragraph lines separated by a large vertical gap', () {
    final raw = [
      rawLine('First paragraph.', top: 0.20, bottom: 0.24, readingOrder: 0),
      rawLine(
        'Second paragraph, far below.',
        top: 0.60,
        bottom: 0.64,
        readingOrder: 1,
      ),
    ];

    final result = useCase('page1', raw);

    expect(result, hasLength(2));
    expect(result[0].text, 'First paragraph.');
    expect(result[1].text, 'Second paragraph, far below.');
  });

  test('merged block confidence is the average of its constituent lines', () {
    final raw = [
      rawLine(
        'Line one',
        top: 0.20,
        bottom: 0.24,
        confidence: 0.8,
        readingOrder: 0,
      ),
      rawLine(
        'line two',
        top: 0.24,
        bottom: 0.28,
        confidence: 0.6,
        readingOrder: 1,
      ),
    ];

    final result = useCase('page1', raw);

    expect(result, hasLength(1));
    expect(result[0].confidence, closeTo(0.7, 1e-9));
  });

  test(
    'reorders a two-column run left-to-right and merges within each column',
    () {
      final raw = [
        rawLine(
          'Wide Title Heading',
          top: 0.06,
          bottom: 0.14,
          left: 0.05,
          right: 0.95,
          readingOrder: 0,
        ),
        rawLine(
          'Left1',
          top: 0.20,
          bottom: 0.23,
          left: 0.1,
          right: 0.4,
          readingOrder: 1,
        ),
        rawLine(
          'Right1',
          top: 0.20,
          bottom: 0.23,
          left: 0.6,
          right: 0.9,
          readingOrder: 2,
        ),
        rawLine(
          'Left2',
          top: 0.24,
          bottom: 0.27,
          left: 0.1,
          right: 0.4,
          readingOrder: 3,
        ),
        rawLine(
          'Right2',
          top: 0.24,
          bottom: 0.27,
          left: 0.6,
          right: 0.9,
          readingOrder: 4,
        ),
      ];

      final result = useCase('page1', raw);

      expect(result, hasLength(3));
      expect(result[0].blockType, BlockType.heading);
      expect(result[0].text, 'Wide Title Heading');
      expect(result[1].text, 'Left1 Left2');
      expect(result[2].text, 'Right1 Right2');
    },
  );

  test('classifies a numbered list item', () {
    final raw = [
      rawLine('1. Do the first thing', top: 0.3, bottom: 0.34, readingOrder: 0),
    ];
    final result = useCase('page1', raw);
    expect(result.single.blockType, BlockType.listItem);
  });

  test('classifies a roman-numeral page number near the bottom margin', () {
    final raw = [rawLine('iv', top: 0.95, bottom: 0.98, readingOrder: 0)];
    final result = useCase('page1', raw);
    expect(result.single.blockType, BlockType.pageNumber);
  });

  test('classifies a quoted line as a quotation', () {
    final raw = [
      rawLine('"To be or not to be"', top: 0.3, bottom: 0.34, readingOrder: 0),
    ];
    final result = useCase('page1', raw);
    expect(result.single.blockType, BlockType.quotation);
  });
}
