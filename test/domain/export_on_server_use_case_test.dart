import 'dart:io';

import 'package:bookscanner/domain/models/export_job.dart';
import 'package:bookscanner/domain/models/provider_info.dart';
import 'package:bookscanner/domain/providers/conversion_api.dart';
import 'package:bookscanner/domain/providers/document_export_provider.dart';
import 'package:bookscanner/domain/repositories/page_path_allocator.dart';
import 'package:bookscanner/domain/use_cases/export_on_server_use_case.dart';
import 'package:bookscanner/domain/use_cases/load_project_page_inputs_use_case.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Records what the app sends and returns a finished job with one artifact.
class _FakeApi implements ConversionApi {
  _FakeApi(this.artifactName);

  final String artifactName;
  String? format;
  Map<String, Object?>? options;

  @override
  Future<ConversionUsage> usage() async =>
      const ConversionUsage(uploadsRemaining: 5, maxUploadBytes: 1 << 30);

  @override
  Future<UploadedDocument> uploadPdf({
    required String pdfPath,
    required String filename,
  }) async => const UploadedDocument(id: 'doc-1', sha256: '');

  @override
  Future<RemoteConversion> startConversion({
    required String documentId,
    required String format,
    required Map<String, Object?> options,
    required String idempotencyKey,
  }) async {
    this.format = format;
    this.options = options;
    return RemoteConversion(
      id: 'job-1',
      state: 'succeeded',
      progressPercent: 100,
      artifacts: [
        RemoteArtifact(
          filename: artifactName,
          sha256: '',
          sizeBytes: 0,
          downloadUrl: '/v1/artifacts/a1',
        ),
      ],
    );
  }

  @override
  Future<RemoteConversion> conversion(String id) =>
      throw UnimplementedError('job is already finished');

  @override
  Future<void> downloadArtifact({
    required String relativeUrl,
    required String destPath,
  }) async {
    await File(destPath).writeAsBytes([0x50, 0x4b, 0x03, 0x04]);
  }
}

class _Pages implements LoadProjectPageInputsUseCase {
  @override
  Future<List<ExportPageInput>> call(String projectId) async => const [
    ExportPageInput(pageId: 'p1', imagePath: '/x/p1.jpg', rotationDegrees: 0),
    ExportPageInput(pageId: 'p2', imagePath: '/x/p2.jpg', rotationDegrees: 0),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LocalPdf implements DocumentExportProvider {
  @override
  Future<ExportOutput> exportPdf(
    ExportDocumentInput input,
    PdfExportOptions options, {
    ExportProgressCallback? onProgress,
  }) async {
    await File(input.outputPathHint).writeAsBytes([0x25, 0x50, 0x44, 0x46]);
    return ExportOutput(
      outputPath: input.outputPathHint,
      providerInfo: const ProviderInfo(
        providerName: 'fake',
        adapterVersion: '1',
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Paths implements PagePathAllocator {
  _Paths(this.root);
  final Directory root;

  @override
  String exportPathFor(String jobId, String extension) =>
      p.join(root.path, '$jobId.$extension');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('export_on_server_test_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('Word goes to the server as docx with title, author and page breaks, '
      'and is saved as a .docx', () async {
    final api = _FakeApi('My Notes.docx');
    final useCase = ExportOnServerUseCase(
      api: api,
      pageLoader: _Pages(),
      exportProvider: _LocalPdf(),
      paths: _Paths(root),
    );

    final saved = await useCase(
      projectId: 'proj',
      title: 'My Notes',
      author: ' Ada ',
      format: ExportFormat.docx,
    );

    expect(api.format, 'docx');
    expect(api.options, {
      'ocr_mode': 'auto',
      'title': 'My Notes',
      'language': 'en',
      'page_breaks': true,
      'author': 'Ada',
    });
    expect(saved, endsWith('.docx'));
    expect(File(saved).existsSync(), isTrue);
  });

  test('Word without an author does not invent one', () async {
    final api = _FakeApi('x.docx');
    await ExportOnServerUseCase(
      api: api,
      pageLoader: _Pages(),
      exportProvider: _LocalPdf(),
      paths: _Paths(root),
    )(projectId: 'proj', title: 'T', format: ExportFormat.docx);

    expect(api.options!.containsKey('author'), isFalse);
  });
}
