package com.quizfactor.bookscanner.bookscanner.capture

/**
 * Mirrors lib/data/services/scanner/scanner_channel_contract.dart. Keep the
 * two files in sync; a mismatch here is caught at runtime by the version
 * check but is a build-time contract by convention (SPEC 9.7: "Maintain one
 * versioned platform contract for commands, events, errors, capabilities,
 * and normalized result models").
 */
object CaptureContract {
    const val CONTRACT_VERSION = 2

    const val METHOD_CHANNEL_NAME = "com.quizfactor.bookscanner/capture"
    const val ANALYSIS_EVENT_CHANNEL_NAME = "com.quizfactor.bookscanner/capture/analysis"

    const val METHOD_CAPABILITIES = "capabilities"
    const val METHOD_OPEN_SESSION = "openSession"
    const val METHOD_CAPTURE_STILL = "captureStill"
    const val METHOD_SET_FLASH_MODE = "setFlashMode"
    const val METHOD_SET_ZOOM = "setZoom"
    const val METHOD_SET_FOCUS_EXPOSURE_POINT = "setFocusAndExposurePoint"
    const val METHOD_CLOSE_SESSION = "closeSession"

    const val ERROR_PERMISSION_DENIED = "PERMISSION_DENIED"
    const val ERROR_UNSUPPORTED_DEVICE = "UNSUPPORTED_DEVICE"
    const val ERROR_MODEL_UNAVAILABLE = "MODEL_UNAVAILABLE"
    const val ERROR_PROCESSING_FAILED = "PROCESSING_FAILED"
    const val ERROR_CANCELLED = "CANCELLED"
    const val ERROR_STORAGE_UNAVAILABLE = "STORAGE_UNAVAILABLE"

    const val PROVIDER_NAME = "native-capture-android"
    const val ADAPTER_VERSION = "2.0.0"
}
