import 'dart:async';
import 'dart:io';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../../domain/models/capture_models.dart';
import '../../../../domain/models/geometry.dart';
import '../../../../domain/models/provider_info.dart';
import '../../../../domain/providers/capture_provider.dart';
import '../../local/app_paths.dart';

/// Production [CaptureProvider] backed by `cunning_document_scanner`
/// (ML Kit Document Scanner on Android, VisionKit on iOS). SPEC 9.6 allows
/// this as a basic-document fallback; it is not the primary book UI.
class CunningDocumentScannerCaptureProvider
    implements CaptureProvider, BatchDocumentCapture {
  CunningDocumentScannerCaptureProvider({required AppPaths paths, Uuid? uuid})
    : _paths = paths,
      _uuid = uuid ?? const Uuid();

  final AppPaths _paths;
  final Uuid _uuid;
  bool _sessionOpen = false;

  @override
  int? get previewTextureId => null;

  @override
  double get previewAspectRatio => 3 / 4;

  @override
  ProviderInfo get info => const ProviderInfo(
    providerName: 'cunning-document-scanner',
    adapterVersion: '1.0.0',
  );

  @override
  Future<ScannerCapabilities> capabilities() async => const ScannerCapabilities(
    liveEdgeDetection: true,
    offlineOcr: false,
    handwritingOcr: false,
    bookDewarping: false,
    fingerRemoval: true,
    supportedOcrLanguages: {},
    torch: false,
    opticalZoom: false,
  );

  @override
  Future<void> openSession(CaptureMode mode) async {
    _sessionOpen = true;
  }

  @override
  Stream<FrameAnalysis> analysisStream() => const Stream.empty();

  /// Opens the native scanner UI and returns every page the user kept.
  /// An empty list means the user cancelled.
  @override
  Future<List<StillCapture>> scanDocuments({int maxPages = 50}) async {
    if (!_sessionOpen) {
      throw const ProviderException(
        ProviderErrorCategory.processingFailed,
        'Session not open',
      );
    }
    try {
      final pictures = await CunningDocumentScanner.getPictures(
        noOfPages: maxPages,
        scannerSource: ScannerSource.camera,
        androidScannerMode: AndroidScannerMode.full,
        iosScannerOptions: IosScannerOptions(
          imageFormat: IosImageFormat.jpg,
          jpgCompressionQuality: 0.92,
        ),
      );
      if (pictures == null) return const [];

      await _paths.originalsDir.create(recursive: true);
      final stills = <StillCapture>[];
      for (final source in pictures) {
        stills.add(await _persistReadyScan(source));
      }
      try {
        await CunningDocumentScanner.cleanCache();
      } catch (_) {}
      return stills;
    } on ProviderException {
      rethrow;
    } on CunningDocumentScannerException catch (e) {
      throw ProviderException(
        e.code == 'permission_denied'
            ? ProviderErrorCategory.permissionDenied
            : ProviderErrorCategory.processingFailed,
        e.message,
        diagnosticCode: e.code,
        providerName: info.providerName,
      );
    } catch (e) {
      throw ProviderException(
        ProviderErrorCategory.unknown,
        e.toString(),
        providerName: info.providerName,
      );
    }
  }

  @override
  Future<StillCapture> captureStill({bool bypassQualityGate = false}) async {
    final stills = await scanDocuments(maxPages: 1);
    if (stills.isEmpty) {
      throw const ProviderException(
        ProviderErrorCategory.cancelled,
        'Scan cancelled',
      );
    }
    return stills.first;
  }

  Future<StillCapture> _persistReadyScan(String sourcePath) async {
    final ext = p.extension(sourcePath).replaceFirst('.', '');
    final dest = p.join(
      _paths.originalsDir.path,
      '${_uuid.v4()}.${ext.isEmpty ? 'jpg' : ext}',
    );
    try {
      await File(sourcePath).copy(dest);
    } on FileSystemException catch (e) {
      throw ProviderException(
        ProviderErrorCategory.storageUnavailable,
        'Could not persist scanned page: $e',
        providerName: info.providerName,
      );
    }
    return StillCapture(
      originalImagePath: dest,
      detectedQuad: Quad.fullFrame,
      qualityScore: 0.9,
      warnings: const {},
      capturedAtMs: DateTime.now().millisecondsSinceEpoch,
      providerInfo: info,
      analyzedFromStill: true,
      detectionConfidence: 1,
      nativeReady: true,
    );
  }

  @override
  Future<void> setFlashMode(FlashMode mode) async {}

  @override
  Future<void> setZoom(double level) async {}

  @override
  Future<void> setFocusAndExposurePoint(double x, double y) async {}

  @override
  Future<void> closeSession() async {
    _sessionOpen = false;
  }
}
