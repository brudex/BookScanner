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
///  - Table detection is a geometric grid heuristic (2+ rows, 3+
///    aligned columns -- 2 columns is indistinguishable from ordinary
///    2-column running text, so real 2-column tables are not detected) --
///    it has no notion of merged/spanning cells, and a caption/legend line
///    touching the grid's edge can be misread as an extra row if it
///    happens to align.
///  - Caption, embedded-image, and QR/barcode blocks are never produced:
///    OCR only sees text lines, not image regions, so there is no reliable
///    signal to detect them from text geometry alone. Building a heuristic
///    for these would be guessing, not detection -- left honestly
///    unimplemented rather than faked.
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
  static final RegExp _footnotePattern = RegExp(r'^(\d{1,2}|\*|†)[\s.]');

  /// Vertical tolerance (as a fraction of [_median] line height) for
  /// clustering cells into the same table row/column in [_detectTableRun].
  static const double _tableRowToleranceMultiplier = 0.4;
  static const double _tableColumnAlignmentTolerance = 0.15;

  List<OcrBlock> call(String pageId, List<OcrBlock> rawLines) {
    if (rawLines.isEmpty) return const [];

    final geo = {for (final line in rawLines) line: _Geometry.of(line)};
    final medianHeight = _median(
      geo.values.map((g) => g.height).toList()..sort(),
    );
    final pageWidth = 1.0;

    // 1. Split into runs separated by "wide" (column-spanning) lines,
    // ordered top-to-bottom. Each run is checked for a table grid first;
    // only non-table runs go through column-run ordering.
    final sorted = [...rawLines]
      ..sort((a, b) => geo[a]!.centerY.compareTo(geo[b]!.centerY));

    final orderedLines = <OcrBlock>[];
    final tableCells = <OcrBlock, (int, int)>{};
    var runStart = 0;
    void flushRun(int endExclusive) {
      if (endExclusive <= runStart) return;
      final run = sorted.sublist(runStart, endExclusive);
      final table = _detectTableRun(run, geo, medianHeight);
      if (table != null) {
        tableCells.addAll(table);
        final cells = table.keys.toList()
          ..sort((a, b) {
            final ra = table[a]!;
            final rb = table[b]!;
            return ra.$1 != rb.$1
                ? ra.$1.compareTo(rb.$1)
                : ra.$2.compareTo(rb.$2);
          });
        orderedLines.addAll(cells);
      } else {
        orderedLines.addAll(_orderColumnRun(run, geo, pageWidth));
      }
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

    // 2. Classify each raw line independently (table cells were already
    // decided by the grid-detection pass above).
    final classified = <OcrBlock, BlockType>{};
    for (final line in orderedLines) {
      classified[line] = tableCells.containsKey(line)
          ? BlockType.tableCell
          : _classifyLine(line, geo[line]!, medianHeight);
    }

    // 3. Merge consecutive same-run "paragraph" lines into single blocks.
    // Table cells are never merged.
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

    // 4. Assign final ids/pageId/readingOrder/blockType/table position.
    return [
      for (var k = 0; k < result.length; k++)
        _finalize(
          result[k],
          pageId,
          k,
          classified[result[k]] ?? BlockType.paragraph,
          tableCells[result[k]],
        ),
    ];
  }

  /// Detects whether [run] forms a table grid: 2+ rows of 3+ cells each,
  /// same cell count per row, with each column's x-position aligned across
  /// rows. Returns a map of each cell line to its (row, column) within the
  /// grid, or null if [run] isn't a table (the common case -- ordinary
  /// paragraph/heading runs never match this shape). Rows are formed by
  /// clustering lines whose `top` values are within a small tolerance of
  /// each other, since real table rows share (near-)identical vertical
  /// position across their cells; a wider tolerance risks merging two
  /// genuinely different lines of body text into a false row.
  Map<OcrBlock, (int, int)>? _detectTableRun(
    List<OcrBlock> run,
    Map<OcrBlock, _Geometry> geo,
    double medianHeight,
  ) {
    if (run.length < 4 || medianHeight <= 0) return null;
    final byTop = [...run]..sort((a, b) => geo[a]!.top.compareTo(geo[b]!.top));
    final rows = <List<OcrBlock>>[];
    for (final line in byTop) {
      final g = geo[line]!;
      if (rows.isNotEmpty &&
          (g.top - geo[rows.last.first]!.top).abs() <=
              medianHeight * _tableRowToleranceMultiplier) {
        rows.last.add(line);
      } else {
        rows.add([line]);
      }
    }

    final gridRows = rows.where((r) => r.length >= 2).toList();
    if (gridRows.length < 2) return null;
    final columnCount = gridRows.first.length;
    if (gridRows.any((r) => r.length != columnCount)) return null;
    // A 2-column result is indistinguishable from an ordinary 2-column
    // running-text layout (every left/right paragraph pair looks like a
    // "2-row, 2-column grid" once lines happen to align) -- confirmed by a
    // false-positive against the multi-column corpus fixture. Real tables
    // overwhelmingly have 3+ columns; require that instead of guessing
    // which 2-column case is which.
    if (columnCount < 3) return null;

    for (final row in gridRows) {
      row.sort((a, b) => geo[a]!.left.compareTo(geo[b]!.left));
    }
    for (var col = 0; col < columnCount; col++) {
      final centerXs = gridRows.map((r) => geo[r[col]]!.centerX).toList();
      final spread =
          centerXs.reduce((a, b) => a > b ? a : b) -
          centerXs.reduce((a, b) => a < b ? a : b);
      if (spread > _tableColumnAlignmentTolerance) return null;
    }

    return {
      for (var r = 0; r < gridRows.length; r++)
        for (var c = 0; c < columnCount; c++) gridRows[r][c]: (r, c),
    };
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
    // A numbered/symbol-marked line in the bottom margin is a footnote, not
    // a plain footer -- footers carry no reference marker (page branding,
    // running header repeat, etc).
    if (isBottomMargin && _footnotePattern.hasMatch(text)) {
      return BlockType.footnote;
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
    BlockType type, [
    (int, int)? tableCell,
  ]) => OcrBlock(
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
    tableRow: tableCell?.$1,
    tableColumn: tableCell?.$2,
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
