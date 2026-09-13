import 'package:uuid/uuid.dart';

import '../models/geometry.dart';
import '../models/ocr_block.dart';

/// Reconstructs page structure from the raw, unclassified lines an
/// [OcrProvider] returns (SPEC 9.4: "Platform OCR output must not be assumed
/// to reconstruct a book automatically — implement layout analysis:
/// paragraph/heading/list/table/caption detection and reading-order
/// resolution for multi-column pages").
///
/// This runs once, identically for both platforms, on top of whatever raw
/// line granularity each native OCR adapter naturally provides — it is
/// deliberately *not* duplicated per-platform.
///
/// Documented limitations (classical heuristics, not ML layout analysis):
///  - Multi-column support is a single left/right split per contiguous run
///    of narrow lines; 3+ column layouts fall back to simple top-to-bottom
///    order.
///  - Headings are a single level (`headingLevel` is always 1); no
///    heading-hierarchy detection.
///  - Table/table-cell detection is not implemented; grid-like content is
///    classified as ordinary paragraphs. A future adapter version could add
///    this without changing the contract.
class AnalyzeOcrLayoutUseCase {
  AnalyzeOcrLayoutUseCase({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;

  static const double _wideLineFraction = 0.6;
  static const double _leftColumnMaxCenterX = 0.45;
  static const double _rightColumnMinCenterX = 0.55;
  static const double _headingHeightMultiplier = 1.3;
  static const double _paragraphMergeGapMultiplier = 0.7;
  static const int _headingMaxChars = 80;
  static final RegExp _pageNumberPattern = RegExp(
    r'^(\d{1,4}|[ivxlcdm]+)$',
    caseSensitive: false,
  );
  static final RegExp _listItemPattern = RegExp(r'^(\d+[.)]\s|[-•*]\s)');

  List<OcrBlock> call(String pageId, List<OcrBlock> rawLines) {
    if (rawLines.isEmpty) return const [];

    final geo = {for (final line in rawLines) line: _Geometry.of(line)};
    final medianHeight = _median(
      geo.values.map((g) => g.height).toList()..sort(),
    );
    final pageWidth = 1.0;

    // 1. Split into runs separated by "wide" (column-spanning) lines,
    // ordered top-to-bottom.
    final sorted = [...rawLines]
      ..sort((a, b) => geo[a]!.centerY.compareTo(geo[b]!.centerY));

    final orderedLines = <OcrBlock>[];
    var runStart = 0;
    void flushRun(int endExclusive) {
      if (endExclusive <= runStart) return;
      final run = sorted.sublist(runStart, endExclusive);
      orderedLines.addAll(_orderColumnRun(run, geo, pageWidth));
    }

    for (var i = 0; i < sorted.length; i++) {
      final g = geo[sorted[i]]!;
      if (g.width > _wideLineFraction * pageWidth) {
        flushRun(i);
        orderedLines.add(sorted[i]);
        runStart = i + 1;
      }
    }
    flushRun(sorted.length);

    // 2. Classify each raw line independently.
    final classified = <OcrBlock, BlockType>{};
    for (final line in orderedLines) {
      classified[line] = _classifyLine(line, geo[line]!, medianHeight);
    }

    // 3. Merge consecutive same-run "paragraph" lines into single blocks.
    final result = <OcrBlock>[];
    var i = 0;
    while (i < orderedLines.length) {
      final line = orderedLines[i];
      final type = classified[line]!;
      if (type != BlockType.paragraph) {
        result.add(line);
        i++;
        continue;
      }
      final group = [line];
      var j = i + 1;
      while (j < orderedLines.length &&
          classified[orderedLines[j]] == BlockType.paragraph &&
          _sameColumn(geo[orderedLines[j - 1]]!, geo[orderedLines[j]]!) &&
          (geo[orderedLines[j]]!.top - geo[orderedLines[j - 1]]!.bottom) <=
              medianHeight * _paragraphMergeGapMultiplier) {
        group.add(orderedLines[j]);
        j++;
      }
      result.add(_merge(group));
      i = j;
    }

    // 4. Assign final ids/pageId/readingOrder/blockType.
    return [
      for (var k = 0; k < result.length; k++)
        _finalize(
          result[k],
          pageId,
          k,
          classified[result[k]] ?? BlockType.paragraph,
        ),
    ];
  }

  /// Orders one contiguous run of non-wide lines: if it splits cleanly into
  /// a left half and a right half (each with >= 2 members), emit left
  /// column top-to-bottom then right column top-to-bottom; otherwise keep
  /// simple top-to-bottom order.
  List<OcrBlock> _orderColumnRun(
    List<OcrBlock> run,
    Map<OcrBlock, _Geometry> geo,
    double pageWidth,
  ) {
    final left = run
        .where((l) => geo[l]!.centerX < _leftColumnMaxCenterX)
        .toList();
    final right = run
        .where((l) => geo[l]!.centerX > _rightColumnMinCenterX)
        .toList();
    final middle = run.length - left.length - right.length;

    if (left.length >= 2 && right.length >= 2 && middle == 0) {
      left.sort((a, b) => geo[a]!.centerY.compareTo(geo[b]!.centerY));
      right.sort((a, b) => geo[a]!.centerY.compareTo(geo[b]!.centerY));
      return [...left, ...right];
    }
    return run; // already sorted by centerY from the caller
  }

  bool _sameColumn(_Geometry a, _Geometry b) {
    final aLeft = a.centerX < _leftColumnMaxCenterX;
    final bLeft = b.centerX < _leftColumnMaxCenterX;
    final aRight = a.centerX > _rightColumnMinCenterX;
    final bRight = b.centerX > _rightColumnMinCenterX;
    if (aLeft || bLeft) return aLeft == bLeft;
    if (aRight || bRight) return aRight == bRight;
    return true;
  }

  BlockType _classifyLine(OcrBlock line, _Geometry g, double medianHeight) {
    final text = line.text.trim();
    if (text.isEmpty) return BlockType.paragraph;

    final isTopMargin = g.centerY < 0.12;
    final isBottomMargin = g.centerY > 0.88;
    if ((isTopMargin || isBottomMargin) && _pageNumberPattern.hasMatch(text)) {
      return BlockType.pageNumber;
    }
    if (g.centerY < 0.08 && text.length <= _headingMaxChars) {
      return BlockType.header;
    }
    if (g.centerY > 0.92 && text.length <= _headingMaxChars) {
      return BlockType.footer;
    }
    if (_listItemPattern.hasMatch(text)) {
      return BlockType.listItem;
    }
    if (text.length <= _headingMaxChars &&
        medianHeight > 0 &&
        g.height >= medianHeight * _headingHeightMultiplier) {
      return BlockType.heading;
    }
    if (text.startsWith('"') || text.startsWith('“')) {
      return BlockType.quotation;
    }
    return BlockType.paragraph;
  }

  OcrBlock _merge(List<OcrBlock> group) {
    if (group.length == 1) return group.first;
    final allPoints = group.expand((b) => b.boundingPolygon.points).toList();
    final minX = allPoints.map((p) => p.x).reduce((a, b) => a < b ? a : b);
    final maxX = allPoints.map((p) => p.x).reduce((a, b) => a > b ? a : b);
    final minY = allPoints.map((p) => p.y).reduce((a, b) => a < b ? a : b);
    final maxY = allPoints.map((p) => p.y).reduce((a, b) => a > b ? a : b);
    return OcrBlock(
      id: '',
      pageId: '',
      boundingPolygon: Polygon([
        Point2D(x: minX, y: minY),
        Point2D(x: maxX, y: minY),
        Point2D(x: maxX, y: maxY),
        Point2D(x: minX, y: maxY),
      ]),
      text: group.map((b) => b.text).join(' '),
      confidence:
          group.map((b) => b.confidence).reduce((a, b) => a + b) / group.length,
      language: group
          .map((b) => b.language)
          .firstWhere((l) => l.isNotEmpty, orElse: () => ''),
      blockType: BlockType.paragraph,
      readingOrder: group.first.readingOrder,
      words: group.expand((b) => b.words).toList(),
    );
  }

  OcrBlock _finalize(
    OcrBlock block,
    String pageId,
    int readingOrder,
    BlockType type,
  ) => OcrBlock(
    id: _uuid.v4(),
    pageId: pageId,
    boundingPolygon: block.boundingPolygon,
    text: block.text,
    confidence: block.confidence,
    language: block.language,
    blockType: type,
    readingOrder: readingOrder,
    words: block.words,
    headingLevel: type == BlockType.heading ? 1 : null,
  );

  double _median(List<double> sorted) {
    if (sorted.isEmpty) return 0;
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[mid]
        : (sorted[mid - 1] + sorted[mid]) / 2;
  }
}

class _Geometry {
  _Geometry({
    required this.top,
    required this.bottom,
    required this.left,
    required this.right,
  });

  final double top;
  final double bottom;
  final double left;
  final double right;

  double get height => bottom - top;
  double get width => right - left;
  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;

  static _Geometry of(OcrBlock block) {
    final points = block.boundingPolygon.points;
    final xs = points.map((p) => p.x);
    final ys = points.map((p) => p.y);
    return _Geometry(
      top: ys.reduce((a, b) => a < b ? a : b),
      bottom: ys.reduce((a, b) => a > b ? a : b),
      left: xs.reduce((a, b) => a < b ? a : b),
      right: xs.reduce((a, b) => a > b ? a : b),
    );
  }
}
