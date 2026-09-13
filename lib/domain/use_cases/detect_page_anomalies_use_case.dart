import 'dart:io';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

import '../models/scan_page.dart';
import '../repositories/ocr_repository.dart';
import '../repositories/page_repository.dart';

class PageAnomalyResult {
  const PageAnomalyResult({
    required this.duplicatesOf,
    required this.likelyMissingBeforeSequence,
  });

  /// Page id -> id of the earlier page it's a likely duplicate of.
  final Map<String, String> duplicatesOf;

  /// Sequence indices where a printed-page-number gap suggests a missing
  /// page before that index.
  final Set<int> likelyMissingBeforeSequence;
}

/// Flags likely duplicate and missing pages (SPEC 6.3): duplicates via two
/// independent signals -- a perceptual average-hash image comparison (real,
/// not a stub — computes an 8x8 grayscale average hash per page and compares
/// Hamming distance) and, for pages that have been OCR'd, a token-overlap
/// text-similarity comparison (catches re-scans of the same physical page
/// under different lighting/crop/rotation that the image hash misses, since
/// it compares recognized words rather than pixels) — plus missing pages via
/// gaps in parsed printed page-number labels. Warnings are reviewable/
/// dismissible by the caller, never block export.
///
/// Hashing runs as a single batched job on a background isolate via
/// [compute] — this use case re-runs after every capture in a session, and
/// decoding every page's image on the UI isolate would make long book
/// sessions increasingly janky (SPEC 11).
class DetectPageAnomaliesUseCase {
  DetectPageAnomaliesUseCase({
    required PageRepository pageRepository,
    required OcrRepository ocrRepository,
  }) : _pageRepository = pageRepository,
       _ocrRepository = ocrRepository;

  final PageRepository _pageRepository;
  final OcrRepository _ocrRepository;

  static const int _hammingDuplicateThreshold = 6;

  /// Jaccard (token-overlap) similarity threshold above which two pages'
  /// recognized text is considered the same page re-scanned, not just
  /// similar content -- deliberately high so unrelated pages that happen to
  /// share common short words never trip this.
  static const double _textSimilarityDuplicateThreshold = 0.85;

  Future<PageAnomalyResult> analyze(String projectId) async {
    final pages = await _pageRepository.getPages(projectId);
    final duplicates = await _findDuplicates(pages);
    await _findTextSimilarDuplicates(pages, duplicates);
    final missing = _findMissingSequenceGaps(pages);
    return PageAnomalyResult(
      duplicatesOf: duplicates,
      likelyMissingBeforeSequence: missing,
    );
  }

  /// Adds to [duplicates] in place, skipping any page already flagged by
  /// the image-hash pass -- this is a secondary, independent signal, not a
  /// replacement for it.
  Future<void> _findTextSimilarDuplicates(
    List<ScanPage> pages,
    Map<String, String> duplicates,
  ) async {
    final tokensByPageId = <String, Set<String>>{};
    for (final page in pages) {
      final blocks = await _ocrRepository.getBlocks(page.id);
      if (blocks.isEmpty) continue;
      final text = blocks.map((b) => b.text).join(' ').toLowerCase();
      final tokens = text
          .split(RegExp(r'\s+'))
          .where((t) => t.isNotEmpty)
          .toSet();
      if (tokens.isNotEmpty) tokensByPageId[page.id] = tokens;
    }

    final ids = tokensByPageId.keys.toList();
    for (var i = 1; i < ids.length; i++) {
      if (duplicates.containsKey(ids[i])) continue;
      for (var j = 0; j < i; j++) {
        final similarity = _jaccardSimilarity(
          tokensByPageId[ids[i]]!,
          tokensByPageId[ids[j]]!,
        );
        if (similarity >= _textSimilarityDuplicateThreshold) {
          duplicates[ids[i]] = ids[j];
          break;
        }
      }
    }
  }

  double _jaccardSimilarity(Set<String> a, Set<String> b) {
    final union = a.union(b).length;
    if (union == 0) return 0;
    return a.intersection(b).length / union;
  }

  Future<Map<String, String>> _findDuplicates(List<ScanPage> pages) async {
    final paths = [
      for (final page in pages)
        page.processedImagePath ?? page.originalImagePath,
    ];
    final hashList = await compute(_hashAllImagesJob, paths);

    final hashes = <String, int>{};
    for (var i = 0; i < pages.length; i++) {
      final hash = hashList[i];
      if (hash != null) hashes[pages[i].id] = hash;
    }

    final duplicates = <String, String>{};
    final ids = hashes.keys.toList();
    for (var i = 1; i < ids.length; i++) {
      for (var j = 0; j < i; j++) {
        final distance = _hammingDistance(hashes[ids[i]]!, hashes[ids[j]]!);
        if (distance <= _hammingDuplicateThreshold) {
          duplicates[ids[i]] = ids[j];
          break;
        }
      }
    }
    return duplicates;
  }

  /// Bit-count of `a ^ b` over a fixed 64-bit width. Deliberately a bounded
  /// loop with an unsigned shift (`>>>`) rather than `while (x != 0) { x >>=
  /// 1; }`: the hash can have its top bit set (it's built from 64 `|=`
  /// bits), and Dart's `>>` is an arithmetic (sign-extending) shift, so a
  /// negative `x` would shift toward -1 forever and never reach 0 — a real
  /// infinite loop this exact code hit during on-device verification.
  int _hammingDistance(int a, int b) {
    var x = a ^ b;
    var count = 0;
    for (var i = 0; i < 64; i++) {
      count += x & 1;
      x >>>= 1;
    }
    return count;
  }

  Set<int> _findMissingSequenceGaps(List<ScanPage> pages) {
    final missing = <int>{};
    int? previousNumber;
    for (final page in pages) {
      final n = _parseLeadingInt(page.logicalPageLabel);
      if (n != null && previousNumber != null && n > previousNumber + 1) {
        missing.add(page.sequence);
      }
      if (n != null) previousNumber = n;
    }
    return missing;
  }

  int? _parseLeadingInt(String? label) {
    if (label == null) return null;
    final match = RegExp(r'^\d+').firstMatch(label.trim());
    if (match == null) return null;
    return int.tryParse(match.group(0)!);
  }
}

List<int?> _hashAllImagesJob(List<String> paths) => [
  for (final path in paths) _averageHash(path),
];

int? _averageHash(String imagePath) {
  try {
    final bytes = File(imagePath).readAsBytesSync();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final small = img.copyResize(decoded, width: 8, height: 8);
    final gray = img.grayscale(small);
    final values = <int>[];
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        values.add(gray.getPixel(x, y).r.toInt());
      }
    }
    final mean = values.reduce((a, b) => a + b) / values.length;
    var hash = 0;
    for (var i = 0; i < values.length; i++) {
      if (values[i] > mean) hash |= (1 << i);
    }
    return hash;
  } on Exception {
    return null;
  }
}
