package com.quizfactor.bookscanner.bookscanner.ocr

import android.content.Context
import android.graphics.Point
import android.graphics.Rect
import android.net.Uri
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Flutter-facing entry point for native OCR (SPEC 9.4). Wraps ML Kit Text
 * Recognition v2 (Latin script, on-device, no network) behind
 * [OcrContract]'s versioned channel. Returns raw per-line results; grouping
 * lines into paragraphs and classifying block types happens once,
 * cross-platform, in Dart's `AnalyzeOcrLayoutUseCase` (SPEC 9.4: "Platform
 * OCR output must not be assumed to reconstruct a book automatically").
 *
 * Known limitation, documented rather than faked: ML Kit's on-device Latin
 * recognizer does not expose a per-word/per-line confidence score in its
 * public API (unlike iOS Vision's `VNRecognizedText.confidence`). Every
 * recognized word/line here is reported with confidence = 1.0 ("no
 * signal"), so SPEC 6.4's low-confidence-flagging review UX will not
 * surface anything on Android until/unless ML Kit exposes this — tracked in
 * IMPLEMENTATION_STATUS.md rather than fabricated.
 *
 * Does not implement [FlutterPlugin.ActivityAware]: recognition operates on
 * a saved file path via the application [Context], with no camera/activity
 * dependency, unlike [com.quizfactor.bookscanner.bookscanner.capture.CapturePlugin].
 */
class OcrPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var methodChannel: MethodChannel? = null
    private var applicationContext: Context? = null
    private val recognizer by lazy { TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS) }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, OcrContract.METHOD_CHANNEL_NAME).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        applicationContext = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            OcrContract.METHOD_SUPPORTED_LANGUAGES -> result.success(listOf("en"))
            OcrContract.METHOD_RECOGNIZE -> handleRecognize(call, result)
            else -> result.notImplemented()
        }
    }

    private fun handleRecognize(call: MethodCall, result: MethodChannel.Result) {
        val context = applicationContext
        val imagePath = call.argument<String>("imagePath")
        if (context == null || imagePath == null) {
            result.error(OcrContract.ERROR_PROCESSING_FAILED, "Missing context or imagePath", null)
            return
        }

        val image: InputImage
        try {
            image = InputImage.fromFilePath(context, Uri.fromFile(File(imagePath)))
        } catch (e: Exception) {
            result.error(OcrContract.ERROR_STORAGE_UNAVAILABLE, e.message, null)
            return
        }

        recognizer.process(image)
            .addOnSuccessListener { text ->
                result.success(mapOf("lines" to flattenLines(text, image.width, image.height)))
            }
            .addOnFailureListener { e ->
                result.error(OcrContract.ERROR_PROCESSING_FAILED, e.message, null)
            }
    }

    private fun flattenLines(text: Text, width: Int, height: Int): List<Map<String, Any?>> {
        val lines = mutableListOf<Map<String, Any?>>()
        for (block in text.textBlocks) {
            for (line in block.lines) {
                lines.add(
                    mapOf(
                        "text" to line.text,
                        "confidence" to 1.0,
                        "language" to (line.recognizedLanguage ?: ""),
                        "boundingPolygon" to polygonFor(line.cornerPoints, line.boundingBox, width, height),
                        "words" to line.elements.map { element ->
                            mapOf(
                                "text" to element.text,
                                "confidence" to 1.0,
                                "boundingPolygon" to polygonFor(element.cornerPoints, element.boundingBox, width, height),
                            )
                        },
                    ),
                )
            }
        }
        return lines
    }

    private fun polygonFor(
        cornerPoints: Array<Point>?,
        boundingBox: Rect?,
        width: Int,
        height: Int,
    ): Map<String, Any?> {
        val safeWidth = if (width > 0) width else 1
        val safeHeight = if (height > 0) height else 1
        val points = if (cornerPoints != null && cornerPoints.size == 4) {
            cornerPoints.map { mapOf("x" to it.x.toDouble() / safeWidth, "y" to it.y.toDouble() / safeHeight) }
        } else {
            val box = boundingBox ?: Rect(0, 0, 0, 0)
            listOf(
                mapOf("x" to box.left.toDouble() / safeWidth, "y" to box.top.toDouble() / safeHeight),
                mapOf("x" to box.right.toDouble() / safeWidth, "y" to box.top.toDouble() / safeHeight),
                mapOf("x" to box.right.toDouble() / safeWidth, "y" to box.bottom.toDouble() / safeHeight),
                mapOf("x" to box.left.toDouble() / safeWidth, "y" to box.bottom.toDouble() / safeHeight),
            )
        }
        return mapOf("points" to points)
    }
}
