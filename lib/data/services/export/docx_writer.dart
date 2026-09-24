import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:image/image.dart' as img;

import '../../../domain/models/export_job.dart';
import '../../../domain/models/ocr_block.dart';
import '../../../domain/models/provider_info.dart';
import '../../../domain/providers/document_export_provider.dart';

/// Hand-rolled, standards-compliant OOXML `.docx` writer (SPEC 6.7). No
/// dependency is available on pub.dev that both (a) writes real OOXML and
/// (b) has no native/vendor SDK, so this generates the package directly: a
/// ZIP containing `[Content_Types].xml`, relationship parts, `word/
/// document.xml`, `word/styles.xml`, and `docProps/core.xml`. Verified by
/// opening the generated file in Word/LibreOffice during manual QA (SPEC 13)
/// and by a round-trip structural test that unzips and parses the XML.
class DocxWriter {
  DocxWriter({required this.info});

  final ProviderInfo info;

  Future<ExportOutput> write(
    ExportDocumentInput input,
    DocxExportOptions options, {
    ExportProgressCallback? onProgress,
  }) async {
    final archive = Archive();
    final mediaEntries = <_MediaEntry>[];

    if (options.pageMode == DocxPageMode.facsimile) {
      for (var i = 0; i < input.pages.length; i++) {
        final bytes = await File(input.pages[i].imagePath).readAsBytes();
        final decoded = img.decodeImage(bytes);
        if (decoded == null) continue;
        mediaEntries.add(
          _MediaEntry(
            index: i,
            fileName: 'image${i + 1}.jpg',
            bytes: img.encodeJpg(decoded, quality: 80),
            widthPx: decoded.width,
            heightPx: decoded.height,
          ),
        );
        onProgress?.call((i + 1) / (input.pages.length * 2));
      }
    }

    final footnotes = <String>[];
    final bodyXml = _buildBody(input, options, mediaEntries, footnotes);

    archive.addFile(
      _textEntry(
        '[Content_Types].xml',
        _contentTypesXml(mediaEntries, footnotes),
      ),
    );
    archive.addFile(_textEntry('_rels/.rels', _rootRelsXml()));
    archive.addFile(_textEntry('docProps/core.xml', _coreXml(input)));
    archive.addFile(_textEntry('word/document.xml', _documentXml(bodyXml)));
    archive.addFile(_textEntry('word/styles.xml', _stylesXml()));
    archive.addFile(
      _textEntry(
        'word/_rels/document.xml.rels',
        _documentRelsXml(mediaEntries, footnotes),
      ),
    );
    if (footnotes.isNotEmpty) {
      archive.addFile(_textEntry('word/footnotes.xml', _footnotesXml(footnotes)));
    }
    for (final m in mediaEntries) {
      archive.addFile(
        ArchiveFile('word/media/${m.fileName}', m.bytes.length, m.bytes),
      );
    }

    final zipBytes = ZipEncoder().encode(archive);
    await File(input.outputPathHint).writeAsBytes(zipBytes);
    onProgress?.call(1.0);

    return ExportOutput(outputPath: input.outputPathHint, providerInfo: info);
  }

  ArchiveFile _textEntry(String path, String content) {
    final bytes = utf8.encode(content);
    return ArchiveFile(path, bytes.length, bytes);
  }

  String _buildBody(
    ExportDocumentInput input,
    DocxExportOptions options,
    List<_MediaEntry> mediaEntries,
    List<String> footnotes,
  ) {
    final buffer = StringBuffer();
    for (var i = 0; i < input.pages.length; i++) {
      final page = input.pages[i];
      if (i > 0 && options.pageMode == DocxPageMode.preservePageBreaks) {
        buffer.write('<w:p><w:r><w:br w:type="page"/></w:r></w:p>');
      }

      if (options.pageMode == DocxPageMode.facsimile) {
        final media = mediaEntries.where((m) => m.index == i).firstOrNull;
        if (media != null) {
          buffer.write(_imageParagraph(media));
        }
      }

      final blocks = [...page.ocrBlocks]
        ..sort((a, b) => a.readingOrder.compareTo(b.readingOrder));
      var k = 0;
      while (k < blocks.length) {
        final block = blocks[k];
        if (block.blockType == BlockType.tableCell) {
          final group = <OcrBlock>[block];
          var j = k + 1;
          while (j < blocks.length &&
              blocks[j].blockType == BlockType.tableCell) {
            group.add(blocks[j]);
            j++;
          }
          buffer.write(_tableXml(group));
          k = j;
          continue;
        }
        if (block.blockType == BlockType.footnote ||
            block.blockType == BlockType.endnote) {
          footnotes.add(_escape(block.text));
          final footnoteId = footnotes.length; // 1-based, matches ordering
          buffer.write(
            '<w:p><w:r><w:rPr><w:rStyle w:val="FootnoteReference"/></w:rPr>'
            '<w:footnoteReference w:id="$footnoteId"/></w:r></w:p>',
          );
          k++;
          continue;
        }
        buffer.write(_blockToXml(block));
        k++;
      }
    }
    return buffer.toString();
  }

  /// Renders a run of consecutive `tableCell` blocks (grouped by
  /// `tableRow`/`tableColumn`) as a real `<w:tbl>`.
  String _tableXml(List<OcrBlock> cells) {
    final byRow = <int, List<OcrBlock>>{};
    for (final cell in cells) {
      byRow.putIfAbsent(cell.tableRow ?? 0, () => []).add(cell);
    }
    final rowKeys = byRow.keys.toList()..sort();
    for (final row in byRow.values) {
      row.sort((a, b) => (a.tableColumn ?? 0).compareTo(b.tableColumn ?? 0));
    }

    String cellXml(OcrBlock cell) =>
        '<w:tc><w:p><w:r><w:t xml:space="preserve">${_escape(cell.text)}</w:t></w:r></w:p></w:tc>';
    String rowXml(List<OcrBlock> row) =>
        '<w:tr>${row.map(cellXml).join()}</w:tr>';

    final buffer = StringBuffer('<w:tbl><w:tblPr/>');
    for (final key in rowKeys) {
      buffer.write(rowXml(byRow[key]!));
    }
    buffer.write('</w:tbl>');
    return buffer.toString();
  }

  String _imageParagraph(_MediaEntry media) {
    const maxWidthEmu = 5943600; // ~6.5in content width
    final aspect = media.heightPx / media.widthPx;
    final widthEmu = maxWidthEmu;
    final heightEmu = (maxWidthEmu * aspect).round();
    final relId = 'rIdImage${media.index + 1}';
    return '''
<w:p><w:r><w:drawing>
<wp:inline distT="0" distB="0" distL="0" distR="0">
<wp:extent cx="$widthEmu" cy="$heightEmu"/>
<wp:docPr id="${media.index + 1}" name="Page ${media.index + 1}"/>
<a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
<a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">
<pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">
<pic:nvPicPr><pic:cNvPr id="${media.index + 1}" name="${media.fileName}"/><pic:cNvPicPr/></pic:nvPicPr>
<pic:blipFill><a:blip r:embed="$relId" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>
<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$widthEmu" cy="$heightEmu"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>
</pic:pic>
</a:graphicData>
</a:graphic>
</wp:inline>
</w:drawing></w:r></w:p>
''';
  }

  String _blockToXml(OcrBlock block) {
    final text = _escape(block.text);
    if (text.isEmpty) return '';
    return switch (block.blockType) {
      BlockType.heading =>
        '<w:p><w:pPr><w:pStyle w:val="Heading${(block.headingLevel ?? 2).clamp(1, 6)}"/></w:pPr><w:r><w:t xml:space="preserve">$text</w:t></w:r></w:p>',
      BlockType.listItem =>
        '<w:p><w:pPr><w:pStyle w:val="ListParagraph"/><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr></w:pPr><w:r><w:t xml:space="preserve">$text</w:t></w:r></w:p>',
      BlockType.pageNumber || BlockType.header || BlockType.footer => '',
      _ => '<w:p><w:r><w:t xml:space="preserve">$text</w:t></w:r></w:p>',
    };
  }

  String _escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  String _documentXml(String body) =>
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing">
<w:body>
$body
<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1417" w:right="1417" w:bottom="1417" w:left="1417"/></w:sectPr>
</w:body>
</w:document>''';

  String _stylesXml() =>
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>
${List.generate(6, (i) => '<w:style w:type="paragraph" w:styleId="Heading${i + 1}"><w:name w:val="heading ${i + 1}"/><w:basedOn w:val="Normal"/><w:pPr><w:outlineLvl w:val="$i"/></w:pPr><w:rPr><w:b/><w:sz w:val="${32 - i * 2}"/></w:rPr></w:style>').join()}
<w:style w:type="paragraph" w:styleId="ListParagraph"><w:name w:val="List Paragraph"/><w:basedOn w:val="Normal"/></w:style>
<w:style w:type="character" w:styleId="FootnoteReference"><w:name w:val="footnote reference"/><w:rPr><w:vertAlign w:val="superscript"/></w:rPr></w:style>
</w:styles>''';

  String _coreXml(ExportDocumentInput input) =>
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
<dc:title>${_escape(input.title)}</dc:title>
${input.author != null ? '<dc:creator>${_escape(input.author!)}</dc:creator>' : ''}
<dc:language>${input.language}</dc:language>
<cp:contentStatus>BookScanner OCR export</cp:contentStatus>
<dcterms:created xsi:type="dcterms:W3CDTF">${DateTime.now().toUtc().toIso8601String()}</dcterms:created>
</cp:coreProperties>''';

  String _contentTypesXml(
    List<_MediaEntry> mediaEntries,
    List<String> footnotes,
  ) =>
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Default Extension="jpg" ContentType="image/jpeg"/>
<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
${footnotes.isEmpty ? '' : '<Override PartName="/word/footnotes.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footnotes+xml"/>'}
</Types>''';

  String _rootRelsXml() =>
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
</Relationships>''';

  String _documentRelsXml(
    List<_MediaEntry> mediaEntries,
    List<String> footnotes,
  ) =>
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
${footnotes.isEmpty ? '' : '<Relationship Id="rIdFootnotes" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footnotes" Target="footnotes.xml"/>'}
${mediaEntries.map((m) => '<Relationship Id="rIdImage${m.index + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/${m.fileName}"/>').join()}
</Relationships>''';

  /// Minimal but complete `word/footnotes.xml` part: the two standard
  /// separator entries every real Word document includes, plus one
  /// `<w:footnote>` per entry in [footnotes], ids matching the
  /// `w:footnoteReference` ids written in the body by [_buildBody].
  String _footnotesXml(List<String> footnotes) =>
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:footnotes xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
<w:footnote w:type="separator" w:id="-1"><w:p><w:r><w:separator/></w:r></w:p></w:footnote>
<w:footnote w:type="continuationSeparator" w:id="0"><w:p><w:r><w:continuationSeparator/></w:r></w:p></w:footnote>
${List.generate(footnotes.length, (i) => '<w:footnote w:id="${i + 1}"><w:p><w:r><w:t xml:space="preserve">${footnotes[i]}</w:t></w:r></w:p></w:footnote>').join()}
</w:footnotes>''';
}

class _MediaEntry {
  _MediaEntry({
    required this.index,
    required this.fileName,
    required this.bytes,
    required this.widthPx,
    required this.heightPx,
  });

  final int index;
  final String fileName;
  final List<int> bytes;
  final int widthPx;
  final int heightPx;
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
