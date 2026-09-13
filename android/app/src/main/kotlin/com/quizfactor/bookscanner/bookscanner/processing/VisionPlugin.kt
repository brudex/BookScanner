package com.quizfactor.bookscanner.bookscanner.processing

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Path-based still processing. Live frames never cross this channel.
 */
class VisionPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        OpenCvScanEngine.init()
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(
                mapOf(
                    "available" to OpenCvScanEngine.init(),
                    "opencvVersion" to OpenCvScanEngine.OPENCV_VERSION,
                    "algorithmVersion" to OpenCvQuadMath.ALGORITHM_VERSION,
                ),
            )
            "detectStill" -> {
                val path = call.argument<String>("path") ?: return result.error("PROCESSING_FAILED", "path required", null)
                worker.execute {
                    val detection = OpenCvScanEngine.detectFromPath(path)
                    val score = OpenCvScanEngine.scorePath(path)
                    main.post {
                        result.success(
                            mapOf(
                                "quad" to detection.quad?.let { quadMap(it.toArray()) },
                                "confidence" to (detection.quad?.confidence ?: 0.0),
                                "rejection" to detection.rejection,
                                "qualityScore" to score,
                                "providerName" to "native-opencv",
                                "adapterVersion" to OpenCvQuadMath.ALGORITHM_VERSION,
                                "opencvVersion" to OpenCvScanEngine.OPENCV_VERSION,
                            ),
                        )
                    }
                }
            }
            "enhanceStill" -> {
                val source = call.argument<String>("sourcePath") ?: return result.error("PROCESSING_FAILED", "sourcePath required", null)
                val dest = call.argument<String>("outputPath") ?: return result.error("PROCESSING_FAILED", "outputPath required", null)
                val cropList = call.argument<List<Double>>("crop")
                val crop = cropList?.toDoubleArray()
                val detectCrop = call.argument<Boolean>("detectCrop") ?: false
                val filter = call.argument<String>("filter") ?: "original"
                val removeShadows = call.argument<Boolean>("removeShadowsAndStains") ?: true
                worker.execute {
                    try {
                        val (applied, score) = OpenCvScanEngine.warpAndEnhance(
                            source, dest, crop, detectCrop, filter, removeShadows,
                        )
                        main.post {
                            result.success(
                                mapOf(
                                    "processedImagePath" to dest,
                                    "crop" to applied?.let { quadMap(it) },
                                    "qualityScore" to score,
                                    "providerName" to "native-opencv",
                                    "adapterVersion" to OpenCvQuadMath.ALGORITHM_VERSION,
                                    "opencvVersion" to OpenCvScanEngine.OPENCV_VERSION,
                                ),
                            )
                        }
                    } catch (e: Exception) {
                        main.post { result.error("PROCESSING_FAILED", e.message, null) }
                    }
                }
            }
            "scoreStill" -> {
                val path = call.argument<String>("path") ?: return result.error("PROCESSING_FAILED", "path required", null)
                worker.execute {
                    val score = OpenCvScanEngine.scorePath(path)
                    main.post { result.success(score) }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun quadMap(q: DoubleArray) = mapOf(
        "topLeft" to mapOf("x" to q[0], "y" to q[1]),
        "topRight" to mapOf("x" to q[2], "y" to q[3]),
        "bottomRight" to mapOf("x" to q[4], "y" to q[5]),
        "bottomLeft" to mapOf("x" to q[6], "y" to q[7]),
    )

    companion object {
        const val CHANNEL = "com.quizfactor.bookscanner/vision"
    }
}
