/// Versioned platform-channel contract shared conceptually with the Kotlin
/// (Android) and Swift (iOS) capture plugin implementations (SPEC 9.7:
/// "Maintain one versioned platform contract for commands, events, errors,
/// capabilities, and normalized result models"). Keep the method/event names
/// and map keys below in sync with:
///   android/app/src/main/kotlin/.../capture/CapturePlugin.kt
///   ios/Runner/Capture/CapturePlugin.swift
class ScannerChannelContract {
  ScannerChannelContract._();

  /// Bump when a breaking change is made to method signatures, event
  /// payload shape, or error categories. Flutter and native adapters both
  /// assert this at session open so a mismatched build fails loudly instead
  /// of silently misbehaving.
  static const int contractVersion = 2;

  static const String methodChannelName = 'com.quizfactor.bookscanner/capture';
  static const String analysisEventChannelName =
      'com.quizfactor.bookscanner/capture/analysis';

  // Methods
  static const String methodCapabilities = 'capabilities';
  static const String methodOpenSession = 'openSession';
  static const String methodCaptureStill = 'captureStill';
  static const String methodSetFlashMode = 'setFlashMode';
  static const String methodSetZoom = 'setZoom';
  static const String methodSetFocusExposurePoint = 'setFocusAndExposurePoint';
  static const String methodCloseSession = 'closeSession';

  // Native platform error codes normalized into ProviderErrorCategory by the
  // adapter. Provider-specific detail is retained as diagnosticCode.
  static const String errorPermissionDenied = 'PERMISSION_DENIED';
  static const String errorUnsupportedDevice = 'UNSUPPORTED_DEVICE';
  static const String errorModelUnavailable = 'MODEL_UNAVAILABLE';
  static const String errorProcessingFailed = 'PROCESSING_FAILED';
  static const String errorCancelled = 'CANCELLED';
  static const String errorStorageUnavailable = 'STORAGE_UNAVAILABLE';
}
