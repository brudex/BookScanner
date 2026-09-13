import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../../../domain/models/export_job.dart';
import '../../../domain/models/ocr_block.dart';
import '../../../domain/models/provider_info.dart';
import '../../../domain/providers/document_export_provider.dart';

/// Generates UTF-8 Markdown with a sibling `assets/` directory (SPEC 6.6).
/// Reading order comes from [OcrBlock.readingOrder]; block type drives the
/// Markdown construct. Tables that don't fit a simple grid fall back to an
/// image of the page region (recorded as a TODO comment for now — see
/// IMPLEMENTATION_STATUS.md) since faithful HTML-table fallback requires the
/// layout stage's per-cell geometry, built in the OCR/layout task.
class MarkdownWriter {
  MarkdownWriter({required this.info});

  final ProviderInfo info;

  Future<ExportOutput> write(
    ExportDocumentInput input,
    MarkdownExportOptions options, {
    ExportProgressCallback? onProgress,
  }) async {
    final outDir = Directory(input.outputPathHint);
    await outDir.create(recursive: true);
    final assetsDir = Directory(p.join(outDir.path, 'assets'));
    await assetsDir.create(recursive: true);

    final buffer = StringBuffer();
    if (options.includeFrontMatter) {
      buffer.writeln('---');
      buffer.writeln('title: "${_escapeYaml(input.title)}"');
      if (input.author != null) {
        buffer.writeln('author: "${_escapeYaml(input.author!)}"');
      }
      buffer.writeln('language: "${input.language}"');
      if (input.isbn != null) buffer.writeln('isbn: "${input.isbn}"');
      buffer.writeln(
        'scan_date: "${DateTime.now().toUtc().toIso8601String()}"',
      );
      buffer.writeln('source: "BookScanner"');
      buffer.writeln('---');
      buffer.writeln();
    }

    final assetPaths = <String>[];
    for (var i = 0; i < input.pages.length; i++) {
      final page = input.pages[i];
      if (options.includePageBoundaryComments) {
        final label = page.logicalPageLabel ?? '${i + 1}';
        buffer.writeln('<!-- Page $label -->');
        buffer.writeln();
      }

      final blocks = [...page.ocrBlocks]
        ..sort((a, b) => a.readingOrder.compareTo(b.readingOrder));
      if (blocks.isEmpty) {
        // No OCR yet for this page: reference the page image directly so the
        // Markdown package remains a faithful, openable artifact.
        final assetName = 'page_${i + 1}${p.extension(page.imagePath)}';
        final assetPath = p.join(assetsDir.path, assetName);
        await File(page.imagePath).copy(assetPath);
        assetPaths.add(assetPath);
        buffer.writeln('![Page ${i + 1}](assets/$assetName)');
        buffer.writeln();
        continue;
      }

      for (final block in blocks) {
        buffer.writeln(_renderBlock(block));
        buffer.writeln();
      }
    }

    final mdPath = p.join(outDir.path, '${_slug(input.title)}.md');
    // File.writeAsString defaults to UTF-8, satisfying SPEC 6.6.
    await File(mdPath).writeAsString(buffer.toString());

    var finalOutput = mdPath;
    if (options.packageAsZip) {
      final zipPath = '${outDir.path}.zip';
      final encoder = ZipFileEncoder();
      encoder.create(zipPath);
      await encoder.addDirectory(outDir);
      await encoder.close();
      finalOutput = zipPath;
    }

    onProgress?.call(1.0);
    return ExportOutput(
      outputPath: finalOutput,
      assetPaths: assetPaths,
      providerInfo: info,
    );
  }

  String _renderBlock(OcrBlock block) => switch (block.blockType) {
    BlockType.heading => '${'#' * (block.headingLevel ?? 2)} ${block.text}',
    BlockType.listItem => '- ${block.text}',
    BlockType.quotation => '> ${block.text}',
    BlockType.caption => '*${block.text}*',
    BlockType.footnote || BlockType.endnote => '[^note]: ${block.text}',
    BlockType.pageNumber || BlockType.header || BlockType.footer => '',
    BlockType.table || BlockType.tableCell => block.text,
    BlockType.image || BlockType.qrBarcode => '',
    BlockType.paragraph || BlockType.unknown => block.text,
  };

  String _escapeYaml(String value) => value.replaceAll('"', '\\"');

  String _slug(String title) {
    final s = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return s.isEmpty ? 'document' : s;
  }
}
