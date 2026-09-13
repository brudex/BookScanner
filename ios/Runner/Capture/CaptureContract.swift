import Foundation

/// Mirrors lib/data/services/scanner/scanner_channel_contract.dart and the
/// Android Kotlin CaptureContract. Keep the three in sync (SPEC 9.7:
/// "Maintain one versioned platform contract for commands, events, errors,
/// capabilities, and normalized result models").
enum CaptureContract {
    static let contractVersion = 2

    static let methodChannelName = "com.quizfactor.bookscanner/capture"
    static let analysisEventChannelName = "com.quizfactor.bookscanner/capture/analysis"

    static let methodCapabilities = "capabilities"
    static let methodOpenSession = "openSession"
    static let methodCaptureStill = "captureStill"
    static let methodSetFlashMode = "setFlashMode"
    static let methodSetZoom = "setZoom"
    static let methodSetFocusExposurePoint = "setFocusAndExposurePoint"
    static let methodCloseSession = "closeSession"

    static let errorPermissionDenied = "PERMISSION_DENIED"
    static let errorUnsupportedDevice = "UNSUPPORTED_DEVICE"
    static let errorModelUnavailable = "MODEL_UNAVAILABLE"
    static let errorProcessingFailed = "PROCESSING_FAILED"
    static let errorCancelled = "CANCELLED"
    static let errorStorageUnavailable = "STORAGE_UNAVAILABLE"

    static let providerName = "native-capture-ios"
    static let adapterVersion = "2.0.0"
}
