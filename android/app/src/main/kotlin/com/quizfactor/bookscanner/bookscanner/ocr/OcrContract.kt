package com.quizfactor.bookscanner.bookscanner.ocr

/**
 * Mirrors `lib/data/services/ocr/ocr_channel_contract.dart`. Keep method
 * names and error codes in sync with that file and with
 * `ios/Runner/Ocr/OcrContract.swift`.
 */
object OcrContract {
    const val CONTRACT_VERSION = 1

    const val METHOD_CHANNEL_NAME = "com.quizfactor.bookscanner/ocr"

    const val METHOD_SUPPORTED_LANGUAGES = "supportedLanguages"
    const val METHOD_RECOGNIZE = "recognize"

    const val ERROR_UNSUPPORTED_DEVICE = "UNSUPPORTED_DEVICE"
    const val ERROR_MODEL_UNAVAILABLE = "MODEL_UNAVAILABLE"
    const val ERROR_PROCESSING_FAILED = "PROCESSING_FAILED"
    const val ERROR_STORAGE_UNAVAILABLE = "STORAGE_UNAVAILABLE"
}
