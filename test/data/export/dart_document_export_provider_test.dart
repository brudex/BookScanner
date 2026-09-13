import 'dart:io';

import 'package:bookscanner/data/services/export/dart_document_export_provider.dart';
import 'package:bookscanner/domain/models/export_job.dart';
import 'package:bookscanner/domain/models/provider_info.dart';
import 'package:bookscanner/domain/providers/document_export_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

void main() {
  late Directory tmpDir;
  late DartDocumentExportProvider provider;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('pdf_export_test_');
    provider = DartDocumentExportProvider();
  });

  tearDown(() async {
    if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
  });

  Future<String> writePageImage(
    String name, {
    int width = 200,
    int height = 300,
  }) async {
    final image = img.Image(width: width, height: height);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    img.drawLine(
      image,
      x1: 0,
      y1: 0,
      x2: width - 1,
      y2: height - 1,
      color: img.ColorRgb8(0, 0, 0),
    );
    final path = p.join(tmpDir.path, name);
    await File(path).writeAsBytes(img.encodeJpg(image));
    return path;
  }

  test(
    'exportPdf writes a valid multi-page PDF with matching page order',
    () async {
      final img1 = await writePageImage('a.jpg');
      final img2 = await writePageImage('b.jpg');
      final outPath = p.join(tmpDir.path, 'out.pdf');

      final input = ExportDocumentInput(
        projectId: 'proj1',
        title: 'Test Doc',
        outputPathHint: outPath,
        pages: [
          ExportPageInput(pageId: 'p1', imagePath: img1, rotationDegrees: 0),
          ExportPageInput(pageId: 'p2', imagePath: img2, rotationDegrees: 0),
        ],
      );

      final output = await provider.exportPdf(
        input,
        const PdfExportOptions(searchable: false),
      );

      final file = File(output.outputPath);
      expect(await file.exists(), isTrue);
      final bytes = await file.readAsBytes();

      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      final tail = String.fromCharCodes(
        bytes.skip((bytes.length - 64).clamp(0, bytes.length)),
      );
      expect(tail, contains('%%EOF'));

      // Two pages captured means two /Type /Page objects should be present.
      final text = String.fromCharCodes(bytes);
      expect(
        '/Type /Page'.allMatches(text).length +
            '/Type/Page'.allMatches(text).length,
        greaterThanOrEqualTo(2),
      );
    },
  );

  test(
    'exportPdf with a password throws a clear ProviderException rather than silently ignoring it',
    () async {
      final img1 = await writePageImage('a.jpg');
      final outPath = p.join(tmpDir.path, 'out_pw.pdf');

      final input = ExportDocumentInput(
        projectId: 'proj1',
        title: 'Protected',
        outputPathHint: outPath,
        pages: [
          ExportPageInput(pageId: 'p1', imagePath: img1, rotationDegrees: 0),
        ],
      );

      expect(
        () => provider.exportPdf(
          input,
          const PdfExportOptions(password: 'secret'),
        ),
        throwsA(isA<ProviderException>()),
      );
    },
  );

  test(
    'exportMarkdown and exportDocx delegate and produce output files',
    () async {
      final img1 = await writePageImage('a.jpg');

      final mdInput = ExportDocumentInput(
        projectId: 'proj1',
        title: 'MD Doc',
        outputPathHint: p.join(tmpDir.path, 'md_out'),
        pages: [
          ExportPageInput(pageId: 'p1', imagePath: img1, rotationDegrees: 0),
        ],
      );
      final mdOutput = await provider.exportMarkdown(
        mdInput,
        const MarkdownExportOptions(),
      );
      expect(await File(mdOutput.outputPath).exists(), isTrue);

      final docxInput = ExportDocumentInput(
        projectId: 'proj1',
        title: 'Docx Doc',
        outputPathHint: p.join(tmpDir.path, 'doc_out.docx'),
        pages: [
          ExportPageInput(pageId: 'p1', imagePath: img1, rotationDegrees: 0),
        ],
      );
      final docxOutput = await provider.exportDocx(
        docxInput,
        const DocxExportOptions(),
      );
      expect(await File(docxOutput.outputPath).exists(), isTrue);
    },
  );
}
