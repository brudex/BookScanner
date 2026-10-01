/// Server conversion of a locally built PDF into Markdown, EPUB, or a
/// searchable PDF. Page size and image quality stay on the phone.
abstract interface class ConversionApi {
  Future<ConversionUsage> usage();

  Future<UploadedDocument> uploadPdf({
    required String pdfPath,
    required String filename,
  });

  Future<RemoteConversion> startConversion({
    required String documentId,
    required String format,
    required Map<String, Object?> options,
    required String idempotencyKey,
  });

  Future<RemoteConversion> conversion(String id);

  Future<void> downloadArtifact({
    required String relativeUrl,
    required String destPath,
  });
}

class ConversionUsage {
  const ConversionUsage({
    required this.uploadsRemaining,
    required this.maxUploadBytes,
    this.resetsAt,
  });

  /// Null means unlimited. Zero means the monthly plan is used up.
  final int? uploadsRemaining;
  final int maxUploadBytes;
  final String? resetsAt;
}

class UploadedDocument {
  const UploadedDocument({required this.id, required this.sha256});

  final String id;
  final String sha256;
}

class RemoteArtifact {
  const RemoteArtifact({
    required this.filename,
    required this.sha256,
    required this.sizeBytes,
    required this.downloadUrl,
  });

  final String filename;
  final String sha256;
  final int sizeBytes;
  final String downloadUrl;
}

class RemoteConversion {
  const RemoteConversion({
    required this.id,
    required this.state,
    required this.progressPercent,
    required this.artifacts,
    this.stage,
    this.errorCode,
    this.errorMessage,
    this.retryAfterSeconds,
  });

  final String id;
  final String state;
  final int? progressPercent;
  final String? stage;
  final String? errorCode;
  final String? errorMessage;
  final int? retryAfterSeconds;
  final List<RemoteArtifact> artifacts;

  bool get isFinished =>
      state == 'succeeded' ||
      state == 'succeeded_with_warnings' ||
      state == 'failed' ||
      state == 'cancelled';
}

class ConversionException implements Exception {
  const ConversionException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}
