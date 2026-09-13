package com.quizfactor.bookscanner.bookscanner.capture

import android.app.Activity
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.lifecycleScope
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.launch

/**
 * Flutter-facing entry point for native capture. Wires the versioned
 * method/event channel contract in [CaptureContract] to
 * [CameraXCaptureController]. This is the only class the Flutter engine
 * talks to; it never leaks CameraX types across the channel (SPEC 9.1, 9.7).
 */
class CapturePlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var controller: CameraXCaptureController? = null
    private var activity: Activity? = null
    private var eventSink: EventChannel.EventSink? = null
    private var flutterPluginBinding: FlutterPlugin.FlutterPluginBinding? = null
    private val mainExecutor by lazy { ContextCompat.getMainExecutor(flutterPluginBinding!!.applicationContext) }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        flutterPluginBinding = binding
        methodChannel = MethodChannel(binding.binaryMessenger, CaptureContract.METHOD_CHANNEL_NAME).also {
            it.setMethodCallHandler(this)
        }
        eventChannel = EventChannel(binding.binaryMessenger, CaptureContract.ANALYSIS_EVENT_CHANNEL_NAME).also {
            it.setStreamHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        methodChannel = null
        eventChannel = null
        flutterPluginBinding = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        val owner = binding.activity as? LifecycleOwner
        if (owner != null) {
            controller = CameraXCaptureController(
                context = binding.activity.applicationContext,
                lifecycleOwner = owner,
                textureRegistry = flutterPluginBinding!!.textureRegistry,
            )
        }
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        controller?.shutdown()
        controller = null
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val owner = activity as? LifecycleOwner
        val ctrl = controller
        if (ctrl == null || owner == null) {
            result.error(CaptureContract.ERROR_UNSUPPORTED_DEVICE, "No activity attached", null)
            return
        }

        when (call.method) {
            CaptureContract.METHOD_CAPABILITIES -> handleCapabilities(ctrl, result)
            CaptureContract.METHOD_OPEN_SESSION -> handleOpenSession(owner, ctrl, result)
            CaptureContract.METHOD_CAPTURE_STILL -> handleCaptureStill(owner, ctrl, result)
            CaptureContract.METHOD_SET_FLASH_MODE -> {
                val mode = call.argument<String>("mode") ?: "off"
                ctrl.setFlashMode(mode)
                result.success(null)
            }
            CaptureContract.METHOD_SET_ZOOM -> {
                val level = (call.argument<Double>("level") ?: 0.0).toFloat()
                ctrl.setZoom(level)
                result.success(null)
            }
            CaptureContract.METHOD_SET_FOCUS_EXPOSURE_POINT -> {
                val x = (call.argument<Double>("x") ?: 0.5).toFloat()
                val y = (call.argument<Double>("y") ?: 0.5).toFloat()
                ctrl.setFocusAndExposurePoint(x, y)
                result.success(null)
            }
            CaptureContract.METHOD_CLOSE_SESSION -> {
                ctrl.close()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun handleCapabilities(ctrl: CameraXCaptureController, result: MethodChannel.Result) {
        result.success(
            mapOf(
                "liveEdgeDetection" to true,
                "offlineOcr" to false,
                "handwritingOcr" to false,
                "bookDewarping" to false,
                "fingerRemoval" to false,
                "supportedOcrLanguages" to emptyList<String>(),
                "torch" to ctrl.hasFlash(),
                "opticalZoom" to ctrl.supportsZoom(),
            ),
        )
    }

    private fun handleOpenSession(owner: LifecycleOwner, ctrl: CameraXCaptureController, result: MethodChannel.Result) {
        ctrl.onFrameAnalysis = { analysis -> dispatchAnalysis(analysis) }
        owner.lifecycleScope.launch {
            try {
                val session = ctrl.open()
                result.success(
                    mapOf(
                        "textureId" to session.textureId,
                        "previewAspectRatio" to session.previewAspectRatio,
                    ),
                )
            } catch (e: CaptureError.UnsupportedDevice) {
                result.error(CaptureContract.ERROR_UNSUPPORTED_DEVICE, e.message, null)
            } catch (e: SecurityException) {
                result.error(CaptureContract.ERROR_PERMISSION_DENIED, e.message, null)
            } catch (e: Exception) {
                result.error(CaptureContract.ERROR_PROCESSING_FAILED, e.message, null)
            }
        }
    }

    private fun handleCaptureStill(owner: LifecycleOwner, ctrl: CameraXCaptureController, result: MethodChannel.Result) {
        owner.lifecycleScope.launch {
            try {
                val still = ctrl.captureStill()
                result.success(
                    mapOf(
                        "originalImagePath" to still.originalImagePath,
                        "detectedQuad" to quadToMap(still.quad),
                        "qualityScore" to still.qualityScore,
                        "warnings" to still.warnings,
                        "capturedAtMs" to still.capturedAtMs,
                        "providerName" to CaptureContract.PROVIDER_NAME,
                        "adapterVersion" to CaptureContract.ADAPTER_VERSION,
                        "modelVersion" to null,
                        "detectionConfidence" to still.confidence,
                        "analyzedFromStill" to still.analyzedFromStill,
                    ),
                )
            } catch (e: CaptureError.ProcessingFailed) {
                result.error(CaptureContract.ERROR_PROCESSING_FAILED, e.message, null)
            } catch (e: Exception) {
                result.error(CaptureContract.ERROR_PROCESSING_FAILED, e.message, null)
            }
        }
    }

    private fun dispatchAnalysis(analysis: FrameAnalysisResult) {
        val sink = eventSink ?: return
        mainExecutor.execute {
            sink.success(
                mapOf(
                    "timestampMs" to analysis.timestampMs,
                    "documentDetected" to analysis.documentDetected,
                    "quad" to quadToMap(analysis.quad),
                    "cornersStable" to analysis.cornersStable,
                    "motionBelowThreshold" to analysis.motionBelowThreshold,
                    "focusAcceptable" to analysis.focusAcceptable,
                    "exposureAcceptable" to analysis.exposureAcceptable,
                    "warnings" to analysis.warnings,
                    "qualityScore" to analysis.qualityScore,
                    "confidence" to analysis.confidence,
                ),
            )
        }
    }

    private fun quadToMap(quad: DoubleArray?): Map<String, Any?>? {
        if (quad == null || quad.size < 8) return null
        return mapOf(
            "topLeft" to mapOf("x" to quad[0], "y" to quad[1]),
            "topRight" to mapOf("x" to quad[2], "y" to quad[3]),
            "bottomRight" to mapOf("x" to quad[4], "y" to quad[5]),
            "bottomLeft" to mapOf("x" to quad[6], "y" to quad[7]),
        )
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }
}
