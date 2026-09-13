import 'package:flutter/services.dart';

import '../../../domain/models/capture_models.dart';
import '../../../domain/models/provider_info.dart';
import 'scanner_channel_contract.dart';

/// Thin Service wrapper around the native capture platform channel (SPEC
/// 9.1: "Treat the platform-channel/plugin wrapper as a Service... Flutter
/// code must depend on stable BookScanner domain interfaces, not directly on
/// CameraX/AVFoundation"). Nothing outside `data/services/scanner/` may
/// import `package:flutter/services.dart` MethodChannel/EventChannel types
/// for capture.
class ScannerPlatformChannel {
  ScannerPlatformChannel({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  }) : _methodChannel =
           methodChannel ??
           const MethodChannel(ScannerChannelContract.methodChannelName),
       _eventChannel =
           eventChannel ??
           const EventChannel(ScannerChannelContract.analysisEventChannelName);

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;

  /// For calls that must return a real value (capabilities, session open,
  /// still capture) — a null result here means the native side responded
  /// with nothing usable, which is itself an error.
  Future<T> _invoke<T>(String method, [Map<String, Object?>? args]) async {
    final result = await _invokeOrNull<T>(method, args);
    if (result == null) {
      throw const ProviderException(
        ProviderErrorCategory.unknown,
        'Null result from native channel',
      );
    }
    return result;
  }

  /// For void-returning commands (`closeSession`, `setFlashMode`, ...) where
  /// the native side legitimately replies with `result.success(nil)` /
  /// `result.success(null)` — that null is the *expected* success value, not
  /// an error. Using [_invoke] here previously threw a spurious
  /// `ProviderException` on every single successful void call, discovered
  /// via an on-device integration test where it silently aborted navigation
  /// after `closeSession()`.
  Future<void> _invokeVoid(String method, [Map<String, Object?>? args]) =>
      _invokeOrNull<void>(method, args);

  Future<T?> _invokeOrNull<T>(
    String method, [
    Map<String, Object?>? args,
  ]) async {
    try {
      return await _methodChannel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw ProviderException(
        _categoryFor(e.code),
        e.message ?? 'Native capture error',
        diagnosticCode: e.code,
        providerName: 'native-channel',
      );
    } on MissingPluginException {
      throw const ProviderException(
        ProviderErrorCategory.unsupportedDevice,
        'Native capture plugin is not registered on this platform',
        providerName: 'native-channel',
      );
    }
  }

  static ProviderErrorCategory _categoryFor(String code) => switch (code) {
    ScannerChannelContract.errorPermissionDenied =>
      ProviderErrorCategory.permissionDenied,
    ScannerChannelContract.errorUnsupportedDevice =>
      ProviderErrorCategory.unsupportedDevice,
    ScannerChannelContract.errorModelUnavailable =>
      ProviderErrorCategory.modelUnavailable,
    ScannerChannelContract.errorProcessingFailed =>
      ProviderErrorCategory.processingFailed,
    ScannerChannelContract.errorCancelled => ProviderErrorCategory.cancelled,
    ScannerChannelContract.errorStorageUnavailable =>
      ProviderErrorCategory.storageUnavailable,
    _ => ProviderErrorCategory.unknown,
  };

  Future<ScannerCapabilities> capabilities() async {
    final map = await _invoke<Map<Object?, Object?>>(
      ScannerChannelContract.methodCapabilities,
    );
    return ScannerCapabilities(
      liveEdgeDetection: map['liveEdgeDetection'] as bool? ?? false,
      offlineOcr: map['offlineOcr'] as bool? ?? false,
      handwritingOcr: map['handwritingOcr'] as bool? ?? false,
      bookDewarping: map['bookDewarping'] as bool? ?? false,
      fingerRemoval: map['fingerRemoval'] as bool? ?? false,
      supportedOcrLanguages:
          (map['supportedOcrLanguages'] as List?)?.cast<String>().toSet() ?? {},
      torch: map['torch'] as bool? ?? false,
      opticalZoom: map['opticalZoom'] as bool? ?? false,
    );
  }

  /// Opens a capture session and returns the Flutter texture id plus the
  /// bound preview aspect ratio for letterboxed rendering.
  Future<({int textureId, double previewAspectRatio})> openSession(
    CaptureMode mode,
  ) async {
    final map = await _invoke<Map<Object?, Object?>>(
      ScannerChannelContract.methodOpenSession,
      {
        'mode': mode.name,
        'contractVersion': ScannerChannelContract.contractVersion,
      },
    );
    final id = map['textureId']!;
    return (
      textureId: id is int ? id : (id as num).toInt(),
      previewAspectRatio:
          (map['previewAspectRatio'] as num?)?.toDouble() ?? 4 / 3,
    );
  }

  Stream<FrameAnalysis> analysisStream() =>
      _eventChannel.receiveBroadcastStream().map(
        (event) =>
            FrameAnalysis.fromChannel((event as Map).cast<Object?, Object?>()),
      );

  Future<StillCapture> captureStill() async {
    final map = await _invoke<Map<Object?, Object?>>(
      ScannerChannelContract.methodCaptureStill,
    );
    return StillCapture.fromChannel(map);
  }

  Future<void> setFlashMode(FlashMode mode) => _invokeVoid(
    ScannerChannelContract.methodSetFlashMode,
    {'mode': mode.name},
  );

  Future<void> setZoom(double level) =>
      _invokeVoid(ScannerChannelContract.methodSetZoom, {'level': level});

  Future<void> setFocusAndExposurePoint(double x, double y) => _invokeVoid(
    ScannerChannelContract.methodSetFocusExposurePoint,
    {'x': x, 'y': y},
  );

  Future<void> closeSession() =>
      _invokeVoid(ScannerChannelContract.methodCloseSession);
}
