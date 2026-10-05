import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../../../domain/models/export_job.dart';
import '../../../domain/models/ocr_block.dart';
import '../../../domain/models/provider_info.dart';
import '../../../domain/providers/document_export_provider.dart';

/// Builds a readable EPUB 3 package from already-processed pages.
///
/// Chapters use stored OCR text when it exists. Page images are embedded
/// when [EpubExportOptions.includePageImages] is set, so a book is still
/// openable before recognition finishes. The `mimetype` entry is stored
/// uncompressed and first, which EPUB readers require.
class EpubWriter {
  EpubWriter({required this.info});

  final ProviderInfo info;

  Future<ExportOutput> write(
    ExportDocumentInput input,
    EpubExportOptions options, {
    ExportProgressCallback? onProgress,
  }) async {
    final archive = Archive();
    final mimetype = utf8.encode('application/epub+zip');
    archive.addFile(
      ArchiveFile('mimetype', mimetype.length, mimetype)
        ..compression = CompressionType.none,
    );

    final images = <_EpubImage>[];
    if (options.includePageImages) {
      for (var i = 0; i < input.pages.length; i++) {
        final page = input.pages[i];
        final file = File(page.imagePath);
        if (!file.existsSync()) continue;
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) continue;
        final ext = p.extension(page.imagePath).toLowerCase();
        final mediaType = ext == '.png' ? 'image/png' : 'image/jpeg';
        final fileName = 'page${i + 1}${ext == '.png' ? '.png' : '.jpg'}';
        images.add(
          _EpubImage(
            index: i,
            fileName: fileName,
            mediaType: mediaType,
            bytes: bytes,
          ),
        );
        archive.addFile(
          ArchiveFile('OEBPS/images/$fileName', bytes.length, bytes),
        );
        onProgress?.call((i + 1) / (input.pages.length + 1));
      }
    }

    archive.addFile(_text('META-INF/container.xml', _containerXml()));
    archive.addFile(_text('OEBPS/style.css', _css()));
    archive.addFile(_text('OEBPS/nav.xhtml', _navXml(input)));
    archive.addFile(_text('OEBPS/content.opf', _opf(input, images)));
    for (var i = 0; i < input.pages.length; i++) {
      final image = images.where((img) => img.index == i).firstOrNull;
      archive.addFile(
        _text('OEBPS/page${i + 1}.xhtml', _chapter(input, i, image)),
      );
    }

    final zipBytes = ZipEncoder().encode(archive);
    await File(input.outputPathHint).writeAsBytes(zipBytes);
    onProgress?.call(1);
    return ExportOutput(outputPath: input.outputPathHint, providerInfo: info);
  }

  ArchiveFile _text(String path, String content) {
    final bytes = utf8.encode(content);
    return ArchiveFile(path, bytes.length, bytes);
  }

  String _chapter(ExportDocumentInput input, int index, _EpubImage? image) {
    final page = input.pages[index];
    final label = page.logicalPageLabel ?? 'Page ${index + 1}';
    final body = StringBuffer();
    if (image != null) {
      body.writeln(
        '<img src="images/${image.fileName}" alt="${_xml(label)}"/>',
      );
    }
    final blocks = [...page.ocrBlocks]
      ..sort((a, b) => a.readingOrder.compareTo(b.readingOrder));
    if (blocks.isEmpty) {
      if (image == null) {
        body.writeln('<p>No recognized text for this page.</p>');
      }
    } else {
      for (final block in blocks) {
        final text = block.text.trim();
        if (text.isEmpty) continue;
        final escaped = _xml(text);
        switch (block.blockType) {
          case BlockType.heading:
            body.writeln('<h2>$escaped</h2>');
          case BlockType.listItem:
            body.writeln('<p>• $escaped</p>');
          case BlockType.quotation:
            body.writeln('<blockquote><p>$escaped</p></blockquote>');
          default:
            body.writeln('<p>$escaped</p>');
        }
      }
    }

    return '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="${_xml(input.language)}">
<head>
  <title>${_xml(label)}</title>
  <link rel="stylesheet" type="text/css" href="style.css"/>
</head>
<body>
  <h1>${_xml(label)}</h1>
  $body
</body>
</html>
''';
  }

  String _opf(ExportDocumentInput input, List<_EpubImage> images) {
    final id = 'book-${input.projectId}';
    final manifest = StringBuffer();
    final spine = StringBuffer();
    for (var i = 0; i < input.pages.length; i++) {
      manifest.writeln(
        '<item id="page${i + 1}" href="page${i + 1}.xhtml" media-type="application/xhtml+xml"/>',
      );
      spine.writeln('<itemref idref="page${i + 1}"/>');
    }
    for (final image in images) {
      manifest.writeln(
        '<item id="img${image.index + 1}" href="images/${image.fileName}" media-type="${image.mediaType}"/>',
      );
    }
    final author = input.author == null
        ? ''
        : '<dc:creator>${_xml(input.author!)}</dc:creator>';
    return '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" unique-identifier="bookid" version="3.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="bookid">$id</dc:identifier>
    <dc:title>${_xml(input.title)}</dc:title>
    <dc:language>${_xml(input.language)}</dc:language>
    $author
    <meta property="dcterms:modified">${DateTime.now().toUtc().toIso8601String()}</meta>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="css" href="style.css" media-type="text/css"/>
    $manifest
  </manifest>
  <spine>
    $spine
  </spine>
</package>
''';
  }

  String _navXml(ExportDocumentInput input) {
    final items = StringBuffer();
    for (var i = 0; i < input.pages.length; i++) {
      final label = input.pages[i].logicalPageLabel ?? 'Page ${i + 1}';
      items.writeln('<li><a href="page${i + 1}.xhtml">${_xml(label)}</a></li>');
    }
    return '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>Contents</title></head>
<body>
  <nav epub:type="toc">
    <h1>${_xml(input.title)}</h1>
    <ol>
      $items
    </ol>
  </nav>
</body>
</html>
''';
  }

  String _containerXml() => '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
''';

  String _css() => '''
body { font-family: serif; line-height: 1.45; margin: 1em; }
img { max-width: 100%; height: auto; margin: 0 0 1em; }
h1 { font-size: 1.3em; }
h2 { font-size: 1.1em; }
''';

  String _xml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

class _EpubImage {
  const _EpubImage({
    required this.index,
    required this.fileName,
    required this.mediaType,
    required this.bytes,
  });

  final int index;
  final String fileName;
  final String mediaType;
  final List<int> bytes;
}
