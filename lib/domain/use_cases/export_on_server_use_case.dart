import 'dart:developer' as developer;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/export_job.dart';
import '../providers/conversion_api.dart';
import '../providers/document_export_provider.dart';
import '../repositories/page_path_allocator.dart';
import 'load_project_page_inputs_use_case.dart';

/// Builds one image PDF on the phone, uploads it, and downloads the
/// server's Markdown ZIP, EPUB, or searchable PDF.
class ExportOnServerUseCase {
  ExportOnServerUseCase({
    required ConversionApi api,
    required LoadProjectPageInputsUseCase pageLoader,
    required DocumentExportProvider exportProvider,
    required PagePathAllocator paths,
    Uuid? uuid,
  }) : _api = api,
       _pageLoader = pageLoader,
       _exportProvider = exportProvider,
       _paths = paths,
       _uuid = uuid ?? const Uuid();

  final ConversionApi _api;
  final LoadProjectPageInputsUseCase _pageLoader;
  final DocumentExportProvider _exportProvider;
  final PagePathAllocator _paths;
  final Uuid _uuid;

  static const _maxPages = 200;
  static const _maxBytes = 100 * 1024 * 1024;

  Future<String> call({
    required String projectId,
    required String title,
    required ExportFormat format,
    String? author,
    PdfExportOptions pdfOptions = const PdfExportOptions(),
    MarkdownExportOptions markdownOptions = const MarkdownExportOptions(),
    DocxExportOptions docxOptions = const DocxExportOptions(),
    void Function(double progress)? onProgress,
  }) async {
    final watch = Stopwatch()..start();
    _log('start ${format.name} project=$projectId');
    final pages = await _pageLoader(projectId);
    _log('loaded ${pages.length} pages in ${watch.elapsed.inMilliseconds}ms');
    if (pages.isEmpty) {
      throw const ConversionException('There are no pages to export.');
    }
    if (pages.length > _maxPages) {
      throw const ConversionException(
        'This document has too many pages. Split it or export fewer than 200 pages.',
      );
    }

    _log('checking API usage');
    final usage = await _api.usage();
    _log(
      'usage remaining=${usage.uploadsRemaining} '
      'maxBytes=${usage.maxUploadBytes}',
    );
    if (usage.uploadsRemaining == 0) {
      throw const ConversionException(
        "You've used all uploads in your plan this month.",
      );
    }

    final uploadId = _uuid.v4();
    final uploadPath = _paths.exportPathFor('upload-$uploadId', 'pdf');
    onProgress?.call(0.02);
    _log('building local image PDF (not the API)');
    await _exportProvider.exportPdf(
      ExportDocumentInput(
        projectId: projectId,
        title: title,
        pages: pages,
        outputPathHint: uploadPath,
        author: author,
      ),
      PdfExportOptions(
        pageSize: pdfOptions.pageSize,
        orientation: pdfOptions.orientation,
        marginPoints: pdfOptions.marginPoints,
        imageQuality: pdfOptions.imageQuality,
        maxDimensionPx: pdfOptions.maxDimensionPx,
        searchable: false,
      ),
    );

    final size = await File(uploadPath).length();
    _log('local PDF ready $size bytes in ${watch.elapsed.inMilliseconds}ms');
    final cap = usage.maxUploadBytes < _maxBytes
        ? usage.maxUploadBytes
        : _maxBytes;
    if (size > cap) {
      throw const ConversionException(
        'This document is too large. Lower the image quality or split it.',
      );
    }

    onProgress?.call(0.08);
    _log('uploading PDF to API');
    final document = await _api.uploadPdf(
      pdfPath: uploadPath,
      filename: '$title.pdf',
    );
    _log('uploaded document ${document.id}');
    final options = _options(
      format,
      title: title,
      author: author,
      markdown: markdownOptions,
      docx: docxOptions,
    );
    _log('starting API conversion ${_serverFormat(format)}');
    final started = await _api.startConversion(
      documentId: document.id,
      format: _serverFormat(format),
      options: options,
      idempotencyKey: _uuid.v4(),
    );

    _log('conversion ${started.id} accepted state=${started.state}');
    var highest = 8;
    var job = started;
    var waitMs = 2000;
    while (!job.isFinished) {
      final seconds = job.retryAfterSeconds;
      _log(
        'waiting on API conversion ${started.id} '
        'state=${job.state} stage=${job.stage}',
      );
      await Future<void>.delayed(
        Duration(milliseconds: seconds != null ? seconds * 1000 : waitMs),
      );
      job = await _api.conversion(started.id);
      final percent = job.progressPercent;
      if (percent != null && percent > highest) highest = percent;
      onProgress?.call(highest / 100);
      waitMs = (waitMs * 1.5).round().clamp(2000, 15000);
    }

    if (job.state == 'cancelled') {
      throw const ConversionException('Export was cancelled.');
    }
    if (job.state == 'failed' || job.artifacts.isEmpty) {
      throw ConversionException(
        job.errorMessage ?? 'Something went wrong. Please try again.',
        code: job.errorCode,
      );
    }

    _log(
      'conversion finished state=${job.state} in ${watch.elapsed.inSeconds}s',
    );
    final artifact = job.artifacts.first;
    final ext = _extension(format, artifact.filename);
    final dest = _paths.exportPathFor(uploadId, ext);
    final temp = '$dest.part';
    _log('downloading API artifact ${artifact.filename}');
    await _api.downloadArtifact(
      relativeUrl: artifact.downloadUrl,
      destPath: temp,
    );
    final downloaded = File(temp);
    final actualSize = await downloaded.length();
    if (artifact.sizeBytes > 0 && actualSize != artifact.sizeBytes) {
      await downloaded.delete();
      throw const ConversionException(
        'The download was incomplete. Try again.',
      );
    }
    if (artifact.sha256.isNotEmpty) {
      final digest = await sha256.bind(downloaded.openRead()).first;
      if (digest.toString() != artifact.sha256) {
        await downloaded.delete();
        throw const ConversionException(
          'The downloaded file did not match. Try again.',
        );
      }
    }
    await downloaded.rename(dest);
    onProgress?.call(1);
    _log('saved $dest in ${watch.elapsed.inSeconds}s');
    return dest;
  }

  void _log(String message) {
    debugPrint('[export] $message');
    developer.log(message, name: 'export');
  }

  String _serverFormat(ExportFormat format) => switch (format) {
    ExportFormat.searchablePdf => 'pdf',
    ExportFormat.markdown => 'markdown_zip',
    ExportFormat.epub => 'epub',
    ExportFormat.docx => 'docx',
    _ => 'pdf',
  };

  Map<String, Object?> _options(
    ExportFormat format, {
    required String title,
    String? author,
    MarkdownExportOptions markdown = const MarkdownExportOptions(),
    DocxExportOptions docx = const DocxExportOptions(),
  }) {
    final trimmedAuthor = author?.trim();
    return switch (format) {
      ExportFormat.epub => {
        'ocr_mode': 'auto',
        'title': title,
        'language': 'en',
        if (trimmedAuthor != null && trimmedAuthor.isNotEmpty)
          'author': trimmedAuthor,
      },
      // Same metadata as EPUB; each scanned page starts a new Word page.
      ExportFormat.docx => {
        'ocr_mode': 'auto',
        'title': title,
        'language': 'en',
        'page_breaks': true,
        // Server default false: one normal reading flow.
        'preserve_layout': docx.preserveLayout,
        if (trimmedAuthor != null && trimmedAuthor.isNotEmpty)
          'author': trimmedAuthor,
      },
      ExportFormat.searchablePdf => {
        'ocr_mode': 'auto',
        'pdf_mode': 'searchable',
        'languages': ['en'],
      },
      // recognize_formulas is accepted only for markdown_zip.
      ExportFormat.markdown => {
        'ocr_mode': 'auto',
        'languages': ['en'],
        'recognize_formulas': markdown.recognizeFormulas,
      },
      _ => {
        'ocr_mode': 'auto',
        'languages': ['en'],
      },
    };
  }

  String _extension(ExportFormat format, String filename) {
    final dot = filename.lastIndexOf('.');
    if (dot > 0 && dot < filename.length - 1) {
      return filename.substring(dot + 1);
    }
    return switch (format) {
      ExportFormat.markdown => 'zip',
      ExportFormat.epub => 'epub',
      ExportFormat.docx => 'docx',
      _ => 'pdf',
    };
  }
}
