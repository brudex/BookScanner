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

/// Copies (and may downscale) a scanner page from [source] to [dest].
typedef StillPersister = Future<void> Function(String source, String dest);

/// Production [CaptureProvider] backed by `cunning_document_scanner`
/// (ML Kit Document Scanner on Android, VisionKit on iOS). Registered as
/// the primary scanner while we compare its results with the in-app camera.
class CunningDocumentScannerCaptureProvider
    implements CaptureProvider, BatchDocumentCapture {
  CunningDocumentScannerCaptureProvider({
    required AppPaths paths,
    Uuid? uuid,
    StillPersister? persistStill,
  }) : _paths = paths,
       _uuid = uuid ?? const Uuid(),
       _persistStill = persistStill ?? _copyStill;

  final AppPaths _paths;
  final Uuid _uuid;

  /// Writes each returned page into app storage. Production bounds the
  /// resolution here (see [StoredPageLimits]); the default copies as-is.
  final StillPersister _persistStill;

  static Future<void> _copyStill(String source, String dest) =>
      File(source).copy(dest);
  bool _sessionOpen = false;
  CaptureMode? _mode;

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
    _mode = mode;
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
        androidScannerMode: androidModeFor(_mode),
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

  /// Books use ML Kit's Base mode: the page is still detected, cropped and
  /// flattened, but the "full" mode's Enhance step brightened paper and
  /// faded faint handwriting, so book pages came out washed out. Look
  /// adjustments stay available in Review. Documents and IDs keep Full
  /// (filters plus stain/finger cleanup).
  static AndroidScannerMode androidModeFor(CaptureMode? mode) =>
      mode == CaptureMode.bookSpread
      ? AndroidScannerMode.base
      : AndroidScannerMode.full;

  Future<StillCapture> _persistReadyScan(String sourcePath) async {
    final ext = p.extension(sourcePath).replaceFirst('.', '');
    final dest = p.join(
      _paths.originalsDir.path,
      '${_uuid.v4()}.${ext.isEmpty ? 'jpg' : ext}',
    );
    try {
      await _persistStill(sourcePath, dest);
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
