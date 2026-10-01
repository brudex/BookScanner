import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../../../domain/providers/conversion_api.dart';

/// Talks to the BookScanner conversion API. Device id stays in secure
/// storage and is never logged.
class BookScannerApiClient implements ConversionApi {
  BookScannerApiClient({
    this.baseUrl = 'https://bookscanner.cachetechs.com',
    FlutterSecureStorage? storage,
    HttpClient? httpClient,
    Uuid? uuid,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _http = httpClient ?? HttpClient(),
       _uuid = uuid ?? const Uuid() {
    _http.connectionTimeout = const Duration(minutes: 2);
  }

  final String baseUrl;
  final FlutterSecureStorage _storage;
  final HttpClient _http;
  final Uuid _uuid;

  static const _deviceKey = 'bookscanner_device_id';
  static const _jsonTimeout = Duration(seconds: 45);
  static const _uploadTimeout = Duration(minutes: 10);

  Future<String> _deviceId() async {
    final existing = await _storage.read(key: _deviceKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final created = 'install-${_uuid.v4()}';
    await _storage.write(key: _deviceKey, value: created);
    return created;
  }

  @override
  Future<ConversionUsage> usage() async {
    final json = await _json('GET', '/v1/usage');
    final limit = json['upload_limit'];
    final remaining = json['uploads_remaining'];
    return ConversionUsage(
      uploadsRemaining: remaining == null ? null : (remaining as num).toInt(),
      maxUploadBytes: int.parse(json['max_upload_bytes'] as String),
      resetsAt: limit == null ? null : json['resets_at'] as String?,
    );
  }

  @override
  Future<UploadedDocument> uploadPdf({
    required String pdfPath,
    required String filename,
  }) async {
    final deviceId = await _deviceId();
    final file = File(pdfPath);
    final boundary = '----bookscanner${_uuid.v4()}';
    final request = await _http.postUrl(Uri.parse('$baseUrl/v1/documents'));
    request.headers.set(
      HttpHeaders.contentTypeHeader,
      'multipart/form-data; boundary=$boundary',
    );
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');

    void addText(String value) => request.add(utf8.encode(value));
    addText('--$boundary\r\n');
    addText('Content-Disposition: form-data; name="deviceId"\r\n\r\n');
    addText('$deviceId\r\n');
    addText('--$boundary\r\n');
    addText(
      'Content-Disposition: form-data; name="file"; filename="${_filename(filename)}"\r\n',
    );
    addText('Content-Type: application/pdf\r\n\r\n');
    await request.addStream(file.openRead());
    addText('\r\n--$boundary--\r\n');

    final response = await _close(
      request,
      'POST /v1/documents (${file.lengthSync()} bytes)',
      _uploadTimeout,
    );
    final body = await _body(response, 'POST /v1/documents', _uploadTimeout);
    final json = _decode(response, body);
    return UploadedDocument(
      id: json['id'] as String,
      sha256: json['sha256'] as String,
    );
  }

  @override
  Future<RemoteConversion> startConversion({
    required String documentId,
    required String format,
    required Map<String, Object?> options,
    required String idempotencyKey,
  }) async {
    final json = await _json(
      'POST',
      '/v1/conversions',
      body: {
        'document_id': documentId,
        'format': format,
        'options': options,
      },
      idempotencyKey: idempotencyKey,
    );
    return _job(json, retryAfter: null);
  }

  @override
  Future<RemoteConversion> conversion(String id) async {
    final deviceId = await _deviceId();
    final request = await _http.getUrl(
      Uri.parse('$baseUrl/v1/conversions/$id'),
    );
    request.headers.set('X-Device-Id', deviceId);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await _close(
      request,
      'GET /v1/conversions/$id',
      _jsonTimeout,
    );
    final body = await _body(response, 'GET /v1/conversions/$id', _jsonTimeout);
    final retry = int.tryParse(response.headers.value('retry-after') ?? '');
    final job = _job(_decode(response, body), retryAfter: retry);
    _log(
      'conversion $id state=${job.state} stage=${job.stage} '
      'progress=${job.progressPercent} retryAfter=${job.retryAfterSeconds}',
    );
    return job;
  }

  @override
  Future<void> downloadArtifact({
    required String relativeUrl,
    required String destPath,
  }) async {
    final deviceId = await _deviceId();
    final request = await _http.getUrl(Uri.parse('$baseUrl$relativeUrl'));
    request.headers.set('X-Device-Id', deviceId);
    final response = await _close(request, 'GET $relativeUrl', _uploadTimeout);
    if (response.statusCode != 200) {
      final body = await _body(response, 'GET $relativeUrl', _jsonTimeout);
      _decode(response, body);
    }
    final file = File(destPath);
    await file.parent.create(recursive: true);
    final sink = file.openWrite();
    try {
      await response.pipe(sink).timeout(_uploadTimeout);
    } on TimeoutException {
      _log('GET $relativeUrl download timed out');
      throw ConversionException(
        'The conversion server stopped responding (GET $relativeUrl).',
        code: 'TIMEOUT',
      );
    }
    _log('downloaded $relativeUrl');
  }

  Future<Map<String, Object?>> _json(
    String method,
    String path, {
    Map<String, Object?>? body,
    String? idempotencyKey,
  }) async {
    final deviceId = await _deviceId();
    final uri = Uri.parse('$baseUrl$path');
    final request = await switch (method) {
      'POST' => _http.postUrl(uri),
      _ => _http.getUrl(uri),
    };
    request.headers.set('X-Device-Id', deviceId);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (idempotencyKey != null) {
      request.headers.set('Idempotency-Key', idempotencyKey);
    }
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(jsonEncode(body)));
    }
    final label = '$method $path';
    final response = await _close(request, label, _jsonTimeout);
    final text = await _body(response, label, _jsonTimeout);
    return _decode(response, text);
  }

  Future<HttpClientResponse> _close(
    HttpClientRequest request,
    String label,
    Duration timeout,
  ) async {
    final watch = Stopwatch()..start();
    _log('$label …');
    try {
      final response = await request.close().timeout(timeout);
      _log('$label ${response.statusCode} in ${watch.elapsed.inMilliseconds}ms');
      return response;
    } on TimeoutException {
      _log('$label timed out after ${watch.elapsed.inSeconds}s');
      throw ConversionException(
        'The conversion server did not respond ($label).',
        code: 'TIMEOUT',
      );
    } on IOException catch (e) {
      _log('$label unreachable: $e');
      throw const ConversionException(
        'Could not reach the conversion server.',
        code: 'NETWORK',
      );
    }
  }

  Future<String> _body(
    HttpClientResponse response,
    String label,
    Duration timeout,
  ) async {
    try {
      return await response.transform(utf8.decoder).join().timeout(timeout);
    } on TimeoutException {
      _log('$label response body timed out');
      throw ConversionException(
        'The conversion server stopped responding ($label).',
        code: 'TIMEOUT',
      );
    }
  }

  Map<String, Object?> _decode(HttpClientResponse response, String body) {
    Map<String, Object?> json = {};
    if (body.isNotEmpty) {
      final decoded = jsonDecode(body);
      if (decoded is Map) json = decoded.cast<String, Object?>();
    }
    if (response.statusCode >= 400) {
      final error = (json['error'] as Map?)?.cast<String, Object?>();
      final code = error?['code'] as String? ?? 'INTERNAL_ERROR';
      _log('API error $code HTTP ${response.statusCode}: ${_snippet(body)}');
      throw ConversionException(_message(code, error), code: code);
    }
    return json;
  }

  RemoteConversion _job(Map<String, Object?> json, {required int? retryAfter}) {
    final error = (json['error'] as Map?)?.cast<String, Object?>();
    final artifacts = (json['artifacts'] as List? ?? const [])
        .map((item) {
          final map = (item as Map).cast<String, Object?>();
          return RemoteArtifact(
            filename: map['filename'] as String? ?? 'export',
            sha256: map['sha256'] as String? ?? '',
            sizeBytes: int.tryParse(map['size_bytes'] as String? ?? '') ?? 0,
            downloadUrl: map['download_url'] as String? ?? '',
          );
        })
        .toList();
    return RemoteConversion(
      id: json['id'] as String,
      state: json['state'] as String? ?? 'queued',
      stage: json['stage'] as String?,
      progressPercent: (json['progress_percent'] as num?)?.toInt(),
      errorCode: error?['code'] as String?,
      errorMessage: error == null
          ? null
          : _message(error['code'] as String? ?? 'INTERNAL_ERROR', error),
      retryAfterSeconds: retryAfter,
      artifacts: artifacts,
    );
  }

  String _message(String code, Map<String, Object?>? error) {
    return switch (code) {
      'UPLOAD_LIMIT_REACHED' =>
        "You've used all uploads in your plan this month.",
      'QUOTA_EXCEEDED' =>
        'You have too many conversions in progress. Please wait for one to finish.',
      'DEVICE_SUSPENDED' =>
        'Your subscription is suspended. Please contact support.',
      'LIMIT_EXCEEDED' =>
        'This document is too large or has too many pages.',
      'INVALID_PDF' => "We couldn't read this file as a PDF.",
      'ENCRYPTED_PDF' => 'This PDF is password-protected.',
      'OCR_REQUIRED' => 'This is a scan; turn on text recognition.',
      'OCR_FAILED' => 'Text recognition failed.',
      'UNSUPPORTED_FORMAT' => "This export isn't available yet.",
      'ARTIFACT_EXPIRED' => 'This download has expired.',
      'UNSUPPORTED_LANGUAGE' => 'That language is not available.',
      _ =>
        error?['message'] as String? ??
            'Something went wrong. Please try again.',
    };
  }

  String _filename(String name) =>
      name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

  String _snippet(String body) {
    final compact = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length <= 180) return compact;
    return '${compact.substring(0, 180)}…';
  }

  void _log(String message) {
    debugPrint('[export] $message');
    developer.log(message, name: 'export');
  }
}
