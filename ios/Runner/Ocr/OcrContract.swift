/// Mirrors `lib/data/services/ocr/ocr_channel_contract.dart`. Keep method
/// names and error codes in sync with that file and with
/// `android/.../ocr/OcrContract.kt`.
enum OcrContract {
    static let contractVersion = 1

    static let methodChannelName = "com.quizfactor.bookscanner/ocr"

    static let methodSupportedLanguages = "supportedLanguages"
    static let methodRecognize = "recognize"

    static let errorUnsupportedDevice = "UNSUPPORTED_DEVICE"
    static let errorModelUnavailable = "MODEL_UNAVAILABLE"
    static let errorProcessingFailed = "PROCESSING_FAILED"
    static let errorStorageUnavailable = "STORAGE_UNAVAILABLE"
}
