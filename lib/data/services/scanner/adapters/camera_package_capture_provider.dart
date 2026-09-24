import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart' as camera;
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../../domain/models/capture_models.dart';
import '../../../../domain/models/geometry.dart';
import '../../../../domain/models/provider_info.dart';
import '../../../../domain/providers/capture_provider.dart';
import '../../local/app_paths.dart';
import '../live_preview_source.dart';

/// Production [CaptureProvider] backed by Flutter's official `camera` plugin
/// (CameraX on Android, AVFoundation on iOS). Selected instead of the
/// first-party CameraX/AVFoundation plugins after the custom Texture bridge
/// stayed black on SM-A055F under both Impeller and Skia.
class CameraPackageCaptureProvider
    implements CaptureProvider, LivePreviewSource {
  CameraPackageCaptureProvider({required AppPaths paths, Uuid? uuid})
    : _paths = paths,
      _uuid = uuid ?? const Uuid();

  final AppPaths _paths;
  final Uuid _uuid;

  camera.CameraController? _controller;
  CaptureMode? _mode;
  StreamController<FrameAnalysis>? _analysis;
  int? _previewTextureId;
  double _previewAspectRatio = 4 / 3;
  bool _analyzingFrame = false;
  double? _lastMeanLuma;

  @override
  int? get previewTextureId => _previewTextureId;

  @override
  double get previewAspectRatio {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return _previewAspectRatio;
    }
    final size = controller.value.previewSize;
    if (size == null || size.height <= 0) return _previewAspectRatio;
    final sensor = size.width / size.height;
    // `CameraPreview` shows an upright portrait buffer; invert landscape
    // sensor sizes so letterboxing matches what the plugin draws.
    return sensor < 1 ? sensor : 1 / sensor;
  }

  @override
  ProviderInfo get info => const ProviderInfo(
    providerName: 'camera-package',
    adapterVersion: '1.0.0',
  );

  @override
  Widget? buildLivePreview() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return null;
    return ClipRect(child: camera.CameraPreview(controller));
  }

  @override
  Future<ScannerCapabilities> capabilities() async {
    return _run(() async {
      final cameras = await camera.availableCameras();
      if (cameras.isEmpty) {
        throw const ProviderException(
          ProviderErrorCategory.unsupportedDevice,
          'No camera available',
        );
      }
      return const ScannerCapabilities(
        liveEdgeDetection: true,
        offlineOcr: false,
        handwritingOcr: false,
        bookDewarping: false,
        fingerRemoval: false,
        supportedOcrLanguages: {},
        torch: true,
        opticalZoom: true,
      );
    });
  }

  @override
  Future<void> openSession(CaptureMode mode) async {
    await _run(() async {
      if (_controller != null &&
          _controller!.value.isInitialized &&
          _mode == mode) {
        return;
      }
      await _disposeController();
      _mode = mode;

      final cameras = await camera.availableCameras();
      camera.CameraDescription? selected;
      for (final description in cameras) {
        if (description.lensDirection == camera.CameraLensDirection.back) {
          selected = description;
          break;
        }
      }
      selected ??= cameras.isEmpty ? null : cameras.first;
      if (selected == null) {
        throw const ProviderException(
          ProviderErrorCategory.unsupportedDevice,
          'No camera available',
        );
      }

      final controller = camera.CameraController(
        selected,
        camera.ResolutionPreset.veryHigh,
        enableAudio: false,
      );
      _controller = controller;
      await controller.initialize();
      _previewTextureId = controller.cameraId;
      final size = controller.value.previewSize;
      if (size != null && size.height > 0) {
        final sensor = size.width / size.height;
        _previewAspectRatio = sensor < 1 ? sensor : 1 / sensor;
      }
      await _analysis?.close();
      _analysis = StreamController<FrameAnalysis>.broadcast();
      await _startAnalysisStream();
    });
  }

  @override
  Stream<FrameAnalysis> analysisStream() =>
      _analysis?.stream ?? const Stream<FrameAnalysis>.empty();

  @override
  Future<StillCapture> captureStill({bool bypassQualityGate = false}) {
    return _run(() async {
      final controller = _controller;
      if (controller == null || !controller.value.isInitialized) {
        throw const ProviderException(
          ProviderErrorCategory.processingFailed,
          'Session not open',
        );
      }
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      final shot = await controller.takePicture();
      await _paths.originalsDir.create(recursive: true);
      final dest = p.join(_paths.originalsDir.path, '${_uuid.v4()}.jpg');
      try {
        await File(shot.path).copy(dest);
      } on FileSystemException catch (e) {
        throw ProviderException(
          ProviderErrorCategory.storageUnavailable,
          'Could not persist captured image: $e',
          providerName: info.providerName,
        );
      }
      try {
        await File(shot.path).delete();
      } catch (_) {}

      await _startAnalysisStream();

      return StillCapture(
        originalImagePath: dest,
        detectedQuad: null,
        qualityScore: 0.5,
        warnings: const {},
        capturedAtMs: DateTime.now().millisecondsSinceEpoch,
        providerInfo: info,
        analyzedFromStill: false,
        detectionConfidence: 0,
      );
    });
  }

  @override
  Future<void> setFlashMode(FlashMode mode) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    await _run(() async {
      await controller.setFlashMode(_toPluginFlash(mode));
    });
  }

  @override
  Future<void> setZoom(double level) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    await _run(() async {
      final min = await controller.getMinZoomLevel();
      final max = await controller.getMaxZoomLevel();
      final zoom = min + level.clamp(0.0, 1.0) * (max - min);
      await controller.setZoomLevel(zoom);
    });
  }

  @override
  Future<void> setFocusAndExposurePoint(double x, double y) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    await _run(() async {
      final point = Offset(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0));
      if (controller.value.focusPointSupported) {
        await controller.setFocusPoint(point);
      }
      if (controller.value.exposurePointSupported) {
        await controller.setExposurePoint(point);
      }
    });
  }

  Future<void> _startAnalysisStream() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      if (controller.value.isStreamingImages) return;
      await controller.startImageStream(_onCameraImage);
    } catch (_) {
      // Preview still works without live analysis.
    }
  }

  void _onCameraImage(camera.CameraImage image) {
    if (_analyzingFrame) return;
    final sink = _analysis;
    if (sink == null || sink.isClosed) return;
    _analyzingFrame = true;
    try {
      sink.add(_analyzePreview(image, _lastMeanLuma));
      _lastMeanLuma = _meanLuma(image);
    } catch (_) {
    } finally {
      _analyzingFrame = false;
    }
  }

  @override
  Future<void> closeSession() async {
    await _analysis?.close();
    _analysis = null;
    _mode = null;
    _lastMeanLuma = null;
    await _disposeController();
  }

  Future<void> _disposeController() async {
    final controller = _controller;
    _controller = null;
    _previewTextureId = null;
    if (controller == null) return;
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {}
    await controller.dispose();
  }

  camera.FlashMode _toPluginFlash(FlashMode mode) => switch (mode) {
    FlashMode.off => camera.FlashMode.off,
    FlashMode.on => camera.FlashMode.always,
    FlashMode.auto => camera.FlashMode.auto,
    FlashMode.torch => camera.FlashMode.torch,
  };

  Future<T> _run<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on ProviderException {
      rethrow;
    } on camera.CameraException catch (e) {
      throw ProviderException(
        _categoryFor(e.code),
        e.description ?? e.code,
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

  ProviderErrorCategory _categoryFor(String code) {
    switch (code) {
      case 'CameraAccessDenied':
      case 'CameraAccessDeniedWithoutPrompt':
      case 'CameraAccessRestricted':
        return ProviderErrorCategory.permissionDenied;
      case 'cameraNotFound':
      case 'Disposed CameraController':
        return ProviderErrorCategory.unsupportedDevice;
      default:
        return ProviderErrorCategory.processingFailed;
    }
  }
}

double _meanLuma(camera.CameraImage image) {
  final y = image.planes.first;
  final w = image.width;
  final h = image.height;
  final stride = y.bytesPerRow;
  final bytes = y.bytes;
  var sum = 0;
  var count = 0;
  const step = 16;
  for (var row = 0; row < h; row += step) {
    final rowStart = row * stride;
    for (var col = 0; col < w; col += step) {
      final i = rowStart + col;
      if (i >= bytes.length) break;
      sum += bytes[i];
      count++;
    }
  }
  return count == 0 ? 0 : sum / count;
}

FrameAnalysis _analyzePreview(camera.CameraImage image, double? lastMean) {
  final y = image.planes.first;
  final w = image.width;
  final h = image.height;
  final stride = y.bytesPerRow;
  final bytes = y.bytes;
  const step = 12;
  var sum = 0;
  var count = 0;
  var centerSum = 0;
  var centerCount = 0;
  var edgeSum = 0;
  var edgeCount = 0;
  var varianceAcc = 0.0;
  final x0 = (w * 0.25).round();
  final x1 = (w * 0.75).round();
  final y0 = (h * 0.25).round();
  final y1 = (h * 0.75).round();
  for (var row = 0; row < h; row += step) {
    final rowStart = row * stride;
    for (var col = 0; col < w; col += step) {
      final i = rowStart + col;
      if (i >= bytes.length) break;
      final v = bytes[i];
      sum += v;
      count++;
      final inCenter = col >= x0 && col < x1 && row >= y0 && row < y1;
      if (inCenter) {
        centerSum += v;
        centerCount++;
      } else {
        edgeSum += v;
        edgeCount++;
      }
    }
  }
  final mean = count == 0 ? 0.0 : sum / count;
  for (var row = 0; row < h; row += step * 2) {
    final rowStart = row * stride;
    for (var col = 0; col < w; col += step * 2) {
      final i = rowStart + col;
      if (i >= bytes.length) break;
      final d = bytes[i] - mean;
      varianceAcc += d * d;
    }
  }
  final samples = (h / (step * 2)) * (w / (step * 2));
  final variance = samples <= 0 ? 0.0 : varianceAcc / samples;
  final centerMean = centerCount == 0 ? mean : centerSum / centerCount;
  final edgeMean = edgeCount == 0 ? mean : edgeSum / edgeCount;
  final paperLike = centerMean > edgeMean + 12;
  final motionLow = lastMean == null || (mean - lastMean).abs() < 8;
  final sharp = variance > 180;
  final exposureOk = mean > 35 && mean < 230;
  final warnings = <QualityWarning>{
    if (!sharp) QualityWarning.blur,
    if (!exposureOk) QualityWarning.lowLight,
  };
  return FrameAnalysis(
    timestampMs: DateTime.now().millisecondsSinceEpoch,
    documentDetected: paperLike,
    quad: paperLike ? Quad.captureGuide : null,
    cornersStable: paperLike && motionLow,
    motionBelowThreshold: motionLow,
    focusAcceptable: sharp,
    exposureAcceptable: exposureOk,
    warnings: warnings,
    confidence: paperLike ? 0.7 : 0,
  );
}
