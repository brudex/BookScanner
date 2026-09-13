import '../models/ocr_block.dart';

abstract interface class OcrRepository {
  Future<List<OcrBlock>> getBlocks(String pageId);

  Stream<List<OcrBlock>> watchBlocks(String pageId);

  Future<void> saveBlocks(String pageId, List<OcrBlock> blocks);

  Future<void> correctBlock(String pageId, String blockId, String newText);

  Future<bool> hasOcr(String pageId);

  /// Full-text search across all OCR text for a project; returns matching
  /// page IDs in reading order.
  Future<List<String>> searchPages(String projectId, String query);
}
