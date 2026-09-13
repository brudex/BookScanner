import 'dart:io';

import 'package:bookscanner/data/services/export/markdown_writer.dart';
import 'package:bookscanner/domain/models/export_job.dart';
import 'package:bookscanner/domain/models/geometry.dart';
import 'package:bookscanner/domain/models/ocr_block.dart';
import 'package:bookscanner/domain/models/provider_info.dart';
import 'package:bookscanner/domain/providers/document_export_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

void main() {
  late Directory tmpDir;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('md_writer_test_');
  });

  tearDown(() async {
    if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
  });

  Future<String> writePageImage(String name) async {
    final image = img.Image(width: 40, height: 40);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    final path = p.join(tmpDir.path, name);
    await File(path).writeAsBytes(img.encodeJpg(image));
    return path;
  }

  test(
    'writes UTF-8 markdown with front matter, heading, and page comment',
    () async {
      final imagePath = await writePageImage('page1.jpg');
      final writer = MarkdownWriter(
        info: const ProviderInfo(providerName: 'test', adapterVersion: '1'),
      );

      final input = ExportDocumentInput(
        projectId: 'proj1',
        title: 'Café Notes',
        author: 'Jane Doe',
        outputPathHint: p.join(tmpDir.path, 'out'),
        pages: [
          ExportPageInput(
            pageId: 'p1',
            imagePath: imagePath,
            rotationDegrees: 0,
            logicalPageLabel: '1',
            ocrBlocks: [
              const OcrBlock(
                id: 'b1',
                pageId: 'p1',
                boundingPolygon: Polygon([Point2D(x: 0, y: 0)]),
                text: 'Chapter One',
                confidence: 0.95,
                language: 'en',
                blockType: BlockType.heading,
                readingOrder: 0,
                headingLevel: 1,
              ),
              const OcrBlock(
                id: 'b2',
                pageId: 'p1',
                boundingPolygon: Polygon([Point2D(x: 0, y: 0)]),
                text: 'Body text follows héré.',
                confidence: 0.9,
                language: 'en',
                blockType: BlockType.paragraph,
                readingOrder: 1,
              ),
            ],
          ),
        ],
      );

      final output = await writer.write(input, const MarkdownExportOptions());

      final file = File(output.outputPath);
      expect(await file.exists(), isTrue);
      final content = await file.readAsString();

      expect(content, contains('title: "Café Notes"'));
      expect(content, contains('author: "Jane Doe"'));
      expect(content, contains('<!-- Page 1 -->'));
      expect(content, contains('# Chapter One'));
      expect(content, contains('Body text follows héré.'));

      // Verify it's valid UTF-8 by round-tripping through the same decoder
      // File.readAsString already uses, and that no replacement characters
      // leaked in from a bad encoding.
      expect(content.contains('�'), isFalse);
    },
  );

  test(
    'falls back to embedding the page image when there is no OCR yet',
    () async {
      final imagePath = await writePageImage('page1.jpg');
      final writer = MarkdownWriter(
        info: const ProviderInfo(providerName: 'test', adapterVersion: '1'),
      );

      final input = ExportDocumentInput(
        projectId: 'proj1',
        title: 'No OCR Yet',
        outputPathHint: p.join(tmpDir.path, 'out2'),
        pages: [
          ExportPageInput(
            pageId: 'p1',
            imagePath: imagePath,
            rotationDegrees: 0,
          ),
        ],
      );

      final output = await writer.write(input, const MarkdownExportOptions());
      final content = await File(output.outputPath).readAsString();

      expect(content, contains('![Page 1](assets/'));
      expect(output.assetPaths, hasLength(1));
      expect(await File(output.assetPaths.single).exists(), isTrue);
    },
  );

  test('packageAsZip produces a zip archive', () async {
    final imagePath = await writePageImage('page1.jpg');
    final writer = MarkdownWriter(
      info: const ProviderInfo(providerName: 'test', adapterVersion: '1'),
    );

    final input = ExportDocumentInput(
      projectId: 'proj1',
      title: 'Zipped',
      outputPathHint: p.join(tmpDir.path, 'out3'),
      pages: [
        ExportPageInput(pageId: 'p1', imagePath: imagePath, rotationDegrees: 0),
      ],
    );

    final output = await writer.write(
      input,
      const MarkdownExportOptions(packageAsZip: true),
    );
    expect(output.outputPath, endsWith('.zip'));
    expect(await File(output.outputPath).exists(), isTrue);
  });
}
