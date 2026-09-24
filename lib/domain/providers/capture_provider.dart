import '../models/capture_models.dart';
import '../models/provider_info.dart';

/// Capability-based contract for a native capture backend (SPEC 9.1, 9.7).
/// Concrete implementations live behind a platform-channel adapter
/// (Kotlin/CameraX, Swift/AVFoundation) or a fake for tests; Flutter feature
/// code depends only on this interface, injected via the composition layer.
abstract interface class CaptureProvider {
  /// Static identity/versioning persisted with derived artifacts.
  ProviderInfo get info;

  /// Capabilities available from this provider on the current device.
  Future<ScannerCapabilities> capabilities();

  /// Opens a capture session for [mode]. Must be called before [analysisStream]
  /// or [captureStill]. Idempotent if already open with the same mode.
  /// After this completes, [previewTextureId] is set if the platform renders
  /// a live preview (some fallback/manual-only providers may leave it null).
  Future<void> openSession(CaptureMode mode);

  /// Flutter `Texture` id backing the live camera preview, or null if this
  /// provider has no live preview (e.g. a manual-import-only fallback).
  int? get previewTextureId;

  /// Width/height of the bound preview buffer, used to letterbox the
  /// Flutter `Texture` instead of stretching it. Defaults to 4:3.
  double get previewAspectRatio;

  /// Reduced-resolution live analysis events for on-screen guidance overlays.
  /// The native side must drop stale frames under load rather than buffer
  /// them (SPEC 9.2 keep-only-latest backpressure).
  Stream<FrameAnalysis> analysisStream();

  /// Captures one full-resolution still from the independently-owned still
  /// pipeline (not derived from an analysis frame). Persists the original
  /// image to app storage immediately and returns its file path.
  /// [bypassQualityGate] is interpreted by the Dart ViewModel; native
  /// adapters still wait for AF/AE and re-detect the saved still.
  Future<StillCapture> captureStill({bool bypassQualityGate = false});

  Future<void> setFlashMode(FlashMode mode);

  /// 0.0 (min) to 1.0 (max optical+digital) zoom.
  Future<void> setZoom(double level);

  /// Normalized (0.0-1.0) tap-to-focus/expose point in preview coordinates.
  Future<void> setFocusAndExposurePoint(double x, double y);

  Future<void> closeSession();
}

/// Optional batch capture used by native document-scanner UIs (SPEC 9.6
/// fallback for documents). Feature code checks `is BatchDocumentCapture`
/// instead of importing a concrete adapter.
abstract interface class BatchDocumentCapture {
  /// Opens the native multi-page scanner and returns every page the user
  /// kept. An empty list means the user cancelled.
  Future<List<StillCapture>> scanDocuments({int maxPages = 50});
}
