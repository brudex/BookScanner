import 'geometry.dart';
import 'provider_info.dart';

/// Capture modes required by SPEC 6.1.
enum CaptureMode { singlePage, batch, bookSpread, idCard, receipt, qrBarcode }

/// Real-time warnings surfaced during live analysis. Never rely on color
/// alone in the UI layer (SPEC 6.11) — each warning carries a text reason.
enum QualityWarning {
  blur,
  glare,
  lowLight,
  clippedEdges,
  severeSkew,
  fingerCovering,
  none,
}

/// Shared live/still detection gate. Below this, Flutter must not treat a
/// quad as a confident automatic crop (BookScannerRevamp: uncertain
/// detections go to manual corner correction).
class DetectionThresholds {
  DetectionThresholds._();

  static const double minConfidence = 0.45;
}

/// Normalized result of one reduced-resolution live-analysis frame. Produced
/// at high frequency by the native side; must never carry raw frame bytes
/// across the platform channel (SPEC 9.1 / 9.2).
class FrameAnalysis {
  const FrameAnalysis({
    required this.timestampMs,
    required this.documentDetected,
    required this.quad,
    required this.cornersStable,
    required this.motionBelowThreshold,
    required this.focusAcceptable,
    required this.exposureAcceptable,
    required this.warnings,
    this.qualityScore = 0,
    this.confidence = 0,
  });

  final int timestampMs;
  final bool documentDetected;
  final Quad? quad;
  final bool cornersStable;
  final bool motionBelowThreshold;
  final bool focusAcceptable;
  final bool exposureAcceptable;
  final Set<QualityWarning> warnings;
  final double qualityScore;

  /// 0-1 document-quad confidence from the native contour pipeline.
  final double confidence;

  /// All auto-capture gates satisfied for this single frame. The provider
  /// still requires these to hold across a stable window before firing.
  bool get gatesSatisfied =>
      documentDetected &&
      cornersStable &&
      motionBelowThreshold &&
      focusAcceptable &&
      exposureAcceptable &&
      (warnings.isEmpty || warnings.single == QualityWarning.none);

  factory FrameAnalysis.fromChannel(Map<Object?, Object?> map) {
    final quadMap = map['quad'] as Map<Object?, Object?>?;
    return FrameAnalysis(
      timestampMs: map['timestampMs'] as int,
      documentDetected: map['documentDetected'] as bool,
      quad: quadMap == null
          ? null
          : Quad.fromJson(quadMap.cast<String, Object?>()),
      cornersStable: map['cornersStable'] as bool,
      motionBelowThreshold: map['motionBelowThreshold'] as bool,
      focusAcceptable: map['focusAcceptable'] as bool,
      exposureAcceptable: map['exposureAcceptable'] as bool,
      warnings: (map['warnings'] as List<Object?>? ?? const [])
          .map((w) => QualityWarning.values.byName(w! as String))
          .toSet(),
      qualityScore: (map['qualityScore'] as num?)?.toDouble() ?? 0,
      confidence: (map['confidence'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Result of a single full-resolution still capture, returned as a file path
/// (never raw bytes) plus the detected quad and quality signals at capture
/// time. SPEC 9.2: "Persist the original still image immediately."
class StillCapture {
  const StillCapture({
    required this.originalImagePath,
    required this.detectedQuad,
    required this.qualityScore,
    required this.warnings,
    required this.capturedAtMs,
    required this.providerInfo,
    this.detectionConfidence = 0,
    this.analyzedFromStill = false,
  });

  final String originalImagePath;
  final Quad? detectedQuad;

  /// 0.0 (unreadable) to 1.0 (excellent).
  final double qualityScore;
  final Set<QualityWarning> warnings;
  final int capturedAtMs;
  final ProviderInfo providerInfo;

  /// Confidence of [detectedQuad] from a still re-detect, not preview.
  final double detectionConfidence;

  /// True when [detectedQuad] / [qualityScore] were computed from the
  /// saved JPEG rather than the last live-analysis frame.
  final bool analyzedFromStill;

  factory StillCapture.fromChannel(Map<Object?, Object?> map) {
    final quadMap = map['detectedQuad'] as Map<Object?, Object?>?;
    return StillCapture(
      originalImagePath: map['originalImagePath']! as String,
      detectedQuad: quadMap == null
          ? null
          : Quad.fromJson(quadMap.cast<String, Object?>()),
      qualityScore: (map['qualityScore'] as num).toDouble(),
      warnings: (map['warnings'] as List<Object?>? ?? const [])
          .map((w) => QualityWarning.values.byName(w! as String))
          .toSet(),
      capturedAtMs: map['capturedAtMs'] as int,
      providerInfo: ProviderInfo(
        providerName: map['providerName']! as String,
        adapterVersion: map['adapterVersion']! as String,
        modelVersion: map['modelVersion'] as String?,
      ),
      detectionConfidence:
          (map['detectionConfidence'] as num?)?.toDouble() ?? 0,
      analyzedFromStill: map['analyzedFromStill'] as bool? ?? false,
    );
  }
}

/// User-configurable capture session settings.
class CaptureSettings {
  const CaptureSettings({
    this.autoCaptureEnabled = true,
    this.countdownSeconds = 0,
    this.continuousCapture = false,
    this.hapticConfirmation = true,
    this.audioConfirmation = true,
    this.flashMode = FlashMode.off,
  });

  final bool autoCaptureEnabled;
  final int countdownSeconds;
  final bool continuousCapture;
  final bool hapticConfirmation;
  final bool audioConfirmation;
  final FlashMode flashMode;

  CaptureSettings copyWith({
    bool? autoCaptureEnabled,
    int? countdownSeconds,
    bool? continuousCapture,
    bool? hapticConfirmation,
    bool? audioConfirmation,
    FlashMode? flashMode,
  }) => CaptureSettings(
    autoCaptureEnabled: autoCaptureEnabled ?? this.autoCaptureEnabled,
    countdownSeconds: countdownSeconds ?? this.countdownSeconds,
    continuousCapture: continuousCapture ?? this.continuousCapture,
    hapticConfirmation: hapticConfirmation ?? this.hapticConfirmation,
    audioConfirmation: audioConfirmation ?? this.audioConfirmation,
    flashMode: flashMode ?? this.flashMode,
  );
}

enum FlashMode { off, on, torch, auto }
