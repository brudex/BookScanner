import 'geometry.dart';

/// Arbitrary polygon (>= 3 points) for OCR/layout bounding regions, which are
/// not always axis-aligned rectangles once dewarping is applied.
class Polygon {
  const Polygon(this.points);

  final List<Point2D> points;

  Map<String, Object?> toJson() => {
    'points': points.map((p) => p.toJson()).toList(),
  };

  factory Polygon.fromJson(Map<String, Object?> json) => Polygon(
    (json['points'] as List)
        .map((p) => Point2D.fromJson((p as Map).cast<String, Object?>()))
        .toList(),
  );
}

enum BlockType {
  heading,
  paragraph,
  listItem,
  table,
  tableCell,
  caption,
  quotation,
  pageNumber,
  header,
  footer,
  footnote,
  endnote,
  image,
  qrBarcode,
  unknown,
}

/// One recognized word or token with its own confidence, used to mark
/// low-confidence spans for review (SPEC 6.4) without discarding the rest of
/// a block.
class OcrWord {
  const OcrWord({
    required this.text,
    required this.boundingPolygon,
    required this.confidence,
  });

  final String text;
  final Polygon boundingPolygon;

  /// 0.0-1.0.
  final double confidence;

  bool get isLowConfidence => confidence < 0.6;
}

/// A single correction the user made to recognized text. Kept as history so
/// re-export always includes corrections without mutating the source page
/// image (SPEC 12 "a new export includes the correction and does not modify
/// the original page image").
class OcrCorrection {
  const OcrCorrection({
    required this.previousText,
    required this.newText,
    required this.correctedAtMs,
  });

  final String previousText;
  final String newText;
  final int correctedAtMs;
}

/// A layout-classified block of recognized text on one page (SPEC 6.4, 10).
class OcrBlock {
  const OcrBlock({
    required this.id,
    required this.pageId,
    required this.boundingPolygon,
    required this.text,
    required this.confidence,
    required this.language,
    required this.blockType,
    required this.readingOrder,
    this.words = const [],
    this.corrections = const [],
    this.tableRow,
    this.tableColumn,
    this.headingLevel,
  });

  final String id;
  final String pageId;
  final Polygon boundingPolygon;

  /// Current text: original recognition or latest user correction.
  final String text;

  /// 0.0-1.0 block-level aggregate confidence.
  final double confidence;
  final String language;
  final BlockType blockType;

  /// Position of this block in the reconstructed reading order for the page
  /// (0-based), independent of on-page pixel position (handles multi-column
  /// layouts).
  final int readingOrder;

  final List<OcrWord> words;
  final List<OcrCorrection> corrections;

  /// Set only when [blockType] is [BlockType.tableCell].
  final int? tableRow;
  final int? tableColumn;

  /// Set only when [blockType] is [BlockType.heading]; 1 = highest level.
  final int? headingLevel;

  bool get isLowConfidence => confidence < 0.6;
  bool get wasCorrected => corrections.isNotEmpty;

  OcrBlock withCorrection(String newText, int correctedAtMs) => OcrBlock(
    id: id,
    pageId: pageId,
    boundingPolygon: boundingPolygon,
    text: newText,
    confidence: 1,
    language: language,
    blockType: blockType,
    readingOrder: readingOrder,
    words: words,
    corrections: [
      ...corrections,
      OcrCorrection(
        previousText: text,
        newText: newText,
        correctedAtMs: correctedAtMs,
      ),
    ],
    tableRow: tableRow,
    tableColumn: tableColumn,
    headingLevel: headingLevel,
  );
}
