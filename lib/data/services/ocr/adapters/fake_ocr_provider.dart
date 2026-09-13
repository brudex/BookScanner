import '../../../../domain/models/geometry.dart';
import '../../../../domain/models/ocr_block.dart';
import '../../../../domain/models/provider_info.dart';
import '../../../../domain/providers/ocr_provider.dart';

/// Deterministic in-memory OCR provider used by contract/unit/widget/
/// integration tests (SPEC 13: "Integration tests must cover ... OCR with a
/// fake adapter"). Not wired into the production composition root on
/// Android or iOS — those use [NativeOcrProvider]. Returns raw, unclassified
/// lines (see [OcrChannelContract] doc comment) shaped like a realistic
/// single page: a heading, a two-line paragraph, a list item, and a page
/// number — enough structure for [AnalyzeOcrLayoutUseCase] to have
/// something non-trivial to classify.
class FakeOcrProvider implements OcrProvider {
  @override
  ProviderInfo get info => const ProviderInfo(
    providerName: 'fake-ocr',
    adapterVersion: '1.0.0-test',
  );

  @override
  bool get requiresNetwork => false;

  @override
  Future<Set<String>> supportedLanguages() async => {'en'};

  @override
  Future<OcrResult> recognize(OcrRequest request) async {
    Polygon lineAt(double top, double bottom) => Polygon([
      Point2D(x: 0.1, y: top),
      Point2D(x: 0.9, y: top),
      Point2D(x: 0.9, y: bottom),
      Point2D(x: 0.1, y: bottom),
    ]);

    OcrWord word(String text, Polygon poly, double confidence) =>
        OcrWord(text: text, boundingPolygon: poly, confidence: confidence);

    final lines = <OcrBlock>[
      OcrBlock(
        id: '',
        pageId: '',
        boundingPolygon: lineAt(0.05, 0.11),
        text: 'Chapter One',
        confidence: 0.97,
        language: 'en',
        blockType: BlockType.unknown,
        readingOrder: 0,
        words: [
          word('Chapter', lineAt(0.05, 0.11), 0.98),
          word('One', lineAt(0.05, 0.11), 0.96),
        ],
      ),
      OcrBlock(
        id: '',
        pageId: '',
        boundingPolygon: lineAt(0.18, 0.22),
        text: 'It was a dark and stormy night, and the old house',
        confidence: 0.91,
        language: 'en',
        blockType: BlockType.unknown,
        readingOrder: 1,
      ),
      OcrBlock(
        id: '',
        pageId: '',
        boundingPolygon: lineAt(0.22, 0.26),
        text: 'creaked with every gust of wind.',
        confidence: 0.89,
        language: 'en',
        blockType: BlockType.unknown,
        readingOrder: 2,
      ),
      OcrBlock(
        id: '',
        pageId: '',
        boundingPolygon: lineAt(0.32, 0.36),
        text: '- First point of interest',
        confidence: 0.85,
        language: 'en',
        blockType: BlockType.unknown,
        readingOrder: 3,
      ),
      OcrBlock(
        id: '',
        pageId: '',
        boundingPolygon: lineAt(0.94, 0.97),
        text: '12',
        confidence: 0.8,
        language: 'en',
        blockType: BlockType.unknown,
        readingOrder: 4,
      ),
    ];
    return OcrResult(blocks: lines, providerInfo: info);
  }
}
