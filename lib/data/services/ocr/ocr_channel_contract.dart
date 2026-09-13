/// Versioned platform-channel contract shared conceptually with the Kotlin
/// (Android) and Swift (iOS) OCR plugin implementations (SPEC 9.7: "Maintain
/// one versioned platform contract for commands, events, errors,
/// capabilities, and normalized result models"). Keep the method names and
/// map keys below in sync with:
///   android/app/src/main/kotlin/.../ocr/OcrPlugin.kt
///   ios/Runner/Ocr/OcrPlugin.swift
///
/// Native adapters return the most granular text unit each platform's SDK
/// naturally recognizes (ML Kit's `Text.TextBlock` on Android, one
/// `VNRecognizedTextObservation` per line on iOS) as a *raw line*. Grouping
/// lines into paragraphs, classifying block types (heading/list/etc.), and
/// computing final reading order is deliberately done once, cross-platform,
/// in [AnalyzeOcrLayoutUseCase] — not duplicated in each native adapter —
/// per SPEC 9.4: "Platform OCR output must not be assumed to reconstruct a
/// book automatically".
class OcrChannelContract {
  OcrChannelContract._();

  static const int contractVersion = 1;

  static const String methodChannelName = 'com.quizfactor.bookscanner/ocr';

  // Methods
  static const String methodSupportedLanguages = 'supportedLanguages';
  static const String methodRecognize = 'recognize';

  // Native platform error codes normalized into ProviderErrorCategory by the
  // adapter.
  static const String errorUnsupportedDevice = 'UNSUPPORTED_DEVICE';
  static const String errorModelUnavailable = 'MODEL_UNAVAILABLE';
  static const String errorProcessingFailed = 'PROCESSING_FAILED';
  static const String errorStorageUnavailable = 'STORAGE_UNAVAILABLE';
}
