import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:bookscanner/data/services/export/docx_writer.dart';
import 'package:bookscanner/domain/models/export_job.dart';
import 'package:bookscanner/domain/models/geometry.dart';
import 'package:bookscanner/domain/models/ocr_block.dart';
import 'package:bookscanner/domain/models/provider_info.dart';
import 'package:bookscanner/domain/providers/document_export_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

void main() {
  late Directory tmpDir;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('docx_writer_test_');
  });

  tearDown(() async {
    if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
  });

  Future<String> writePageImage(String name) async {
    final image = img.Image(width: 80, height: 120);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    final path = p.join(tmpDir.path, name);
    await File(path).writeAsBytes(img.encodeJpg(image));
    return path;
  }

  ExportDocumentInput buildInput(String outPath, {required bool withImage}) =>
      ExportDocumentInput(
        projectId: 'proj1',
        title: 'Structural Test',
        author: 'Author X',
        outputPathHint: outPath,
        pages: [
          ExportPageInput(
            pageId: 'p1',
            imagePath: withImage ? '' : '',
            rotationDegrees: 0,
            ocrBlocks: [
              const OcrBlock(
                id: 'b1',
                pageId: 'p1',
                boundingPolygon: Polygon([Point2D(x: 0, y: 0)]),
                text: 'Section Heading',
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
                text: 'A body paragraph with unicode: café.',
                confidence: 0.9,
                language: 'en',
                blockType: BlockType.paragraph,
                readingOrder: 1,
              ),
              const OcrBlock(
                id: 'b3',
                pageId: 'p1',
                boundingPolygon: Polygon([Point2D(x: 0, y: 0)]),
                text: 'A bullet item',
                confidence: 0.9,
                language: 'en',
                blockType: BlockType.listItem,
                readingOrder: 2,
              ),
            ],
          ),
        ],
      );

  test('produces a well-formed OOXML package (reflowable mode)', () async {
    final outPath = p.join(tmpDir.path, 'out.docx');
    final writer = DocxWriter(
      info: const ProviderInfo(providerName: 'test', adapterVersion: '1'),
    );

    final output = await writer.write(
      buildInput(outPath, withImage: false),
      const DocxExportOptions(),
    );

    final bytes = await File(output.outputPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final names = archive.files.map((f) => f.name).toSet();

    expect(
      names,
      containsAll(<String>[
        '[Content_Types].xml',
        '_rels/.rels',
        'word/document.xml',
        'word/styles.xml',
        'word/_rels/document.xml.rels',
        'docProps/core.xml',
      ]),
    );

    final documentXml = utf8.decode(
      archive.findFile('word/document.xml')!.content as List<int>,
    );
    // Must parse as well-formed XML.
    final parsed = XmlDocument.parse(documentXml);
    expect(parsed.rootElement.name.local, 'document');

    expect(documentXml, contains('Section Heading'));
    expect(documentXml, contains('Heading1'));
    expect(documentXml, contains('café'));
    expect(documentXml, contains('ListParagraph'));

    final coreXml = utf8.decode(
      archive.findFile('docProps/core.xml')!.content as List<int>,
    );
    XmlDocument.parse(coreXml); // must not throw
    expect(coreXml, contains('Structural Test'));
    expect(coreXml, contains('Author X'));
  });

  test('facsimile mode embeds page images as media parts', () async {
    final outPath = p.join(tmpDir.path, 'out_facsimile.docx');
    final imagePath = await writePageImage('p1.jpg');
    final writer = DocxWriter(
      info: const ProviderInfo(providerName: 'test', adapterVersion: '1'),
    );

    final input = ExportDocumentInput(
      projectId: 'proj1',
      title: 'Facsimile Test',
      outputPathHint: outPath,
      pages: [
        ExportPageInput(pageId: 'p1', imagePath: imagePath, rotationDegrees: 0),
      ],
    );

    final output = await writer.write(
      input,
      const DocxExportOptions(pageMode: DocxPageMode.facsimile),
    );
    final bytes = await File(output.outputPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final names = archive.files.map((f) => f.name).toSet();

    expect(names, contains('word/media/image1.jpg'));
    final rels = utf8.decode(
      archive.findFile('word/_rels/document.xml.rels')!.content as List<int>,
    );
    expect(rels, contains('media/image1.jpg'));
  });

  test(
    'preservePageBreaks mode inserts explicit page breaks between pages',
    () async {
      final outPath = p.join(tmpDir.path, 'out_breaks.docx');
      final writer = DocxWriter(
        info: const ProviderInfo(providerName: 'test', adapterVersion: '1'),
      );

      final input = ExportDocumentInput(
        projectId: 'proj1',
        title: 'Breaks',
        outputPathHint: outPath,
        pages: [
          ExportPageInput(
            pageId: 'p1',
            imagePath: '',
            rotationDegrees: 0,
            ocrBlocks: [
              const OcrBlock(
                id: 'b1',
                pageId: 'p1',
                boundingPolygon: Polygon([Point2D(x: 0, y: 0)]),
                text: 'Page one text',
                confidence: 0.9,
                language: 'en',
                blockType: BlockType.paragraph,
                readingOrder: 0,
              ),
            ],
          ),
          ExportPageInput(
            pageId: 'p2',
            imagePath: '',
            rotationDegrees: 0,
            ocrBlocks: [
              const OcrBlock(
                id: 'b2',
                pageId: 'p2',
                boundingPolygon: Polygon([Point2D(x: 0, y: 0)]),
                text: 'Page two text',
                confidence: 0.9,
                language: 'en',
                blockType: BlockType.paragraph,
                readingOrder: 0,
              ),
            ],
          ),
        ],
      );

      final output = await writer.write(
        input,
        const DocxExportOptions(pageMode: DocxPageMode.preservePageBreaks),
      );
      final bytes = await File(output.outputPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final documentXml = utf8.decode(
        archive.findFile('word/document.xml')!.content as List<int>,
      );

      expect(documentXml, contains('w:br w:type="page"'));
      expect(documentXml, contains('Page one text'));
      expect(documentXml, contains('Page two text'));
    },
  );
}
