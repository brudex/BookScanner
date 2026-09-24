package com.quizfactor.bookscanner.bookscanner.capture

import android.app.Activity
import android.content.Context
import android.media.MediaActionSound
import android.util.Log
import android.util.Size
import android.view.Surface
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.FocusMeteringAction
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.core.SurfaceOrientedMeteringPointFactory
import androidx.camera.core.SurfaceRequest
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.quizfactor.bookscanner.bookscanner.processing.OpenCvScanEngine
import io.flutter.view.TextureRegistry
import java.io.File
import java.util.UUID
import java.util.concurrent.Executor
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.coroutines.suspendCoroutine
import kotlinx.coroutines.delay

sealed class CaptureError(message: String) : Exception(message) {
    class PermissionDenied(message: String) : CaptureError(message)
    class UnsupportedDevice(message: String) : CaptureError(message)
    class ProcessingFailed(message: String) : CaptureError(message)
}

data class StillCaptureResult(
    val originalImagePath: String,
    val quad: DoubleArray?,
    val qualityScore: Double,
    val warnings: List<String>,
    val capturedAtMs: Long,
    val confidence: Double = 0.0,
    val analyzedFromStill: Boolean = false,
)

data class OpenSessionResult(
    val textureId: Long,
    val previewAspectRatio: Double,
)

/**
 * Owns the CameraX session lifecycle, the live-analysis pipeline, and still
 * capture. This class is the only place in the Android app that imports
 * `androidx.camera.*` — [CapturePlugin] translates its results into the
 * platform-channel contract, and no Dart code ever sees a CameraX type
 * (SPEC 9.1, 9.7).
 */
class CameraXCaptureController(
    private val context: Context,
    private val lifecycleOwner: LifecycleOwner,
    private val textureRegistry: TextureRegistry,
) {
    companion object {
        private const val TAG = "CameraXCapture"
    }
    private var cameraProvider: ProcessCameraProvider? = null
    private var camera: Camera? = null
    private var imageCapture: ImageCapture? = null
    private var imageAnalysis: ImageAnalysis? = null
    // Skia GLES + SurfaceTexture. Impeller Vulkan cannot sample a
    // SurfaceTexture, and the API-29+ ImageReader SurfaceProducer stays
    // black with CameraX Preview on this device (ImageAnalysis still runs).
    // Impeller is disabled in AndroidManifest until that path works.
    private var textureEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var analyzer: CaptureAnalyzer? = null

    private val analysisExecutor: Executor = Executors.newSingleThreadExecutor()
    private val mainExecutor: Executor = ContextCompat.getMainExecutor(context)

    // CameraX's ImageCapture, unlike iOS's AVCapturePhotoOutput, does not
    // play a shutter sound on its own -- an app has to trigger one itself
    // to give the same "capture happened" feedback stock camera apps do.
    private val shutterSound = MediaActionSound()

    private val capturesDir: File by lazy {
        File(context.filesDir, "captures").apply { mkdirs() }
    }

    var onFrameAnalysis: ((FrameAnalysisResult) -> Unit)? = null

    /// Last live-analysis result — guidance only. The saved still is
    /// re-detected independently after the JPEG is on disk.
    private var lastAnalysis: FrameAnalysisResult? = null
    var previewAspectRatio: Double = 4.0 / 3.0
        private set

    fun hasFlash(): Boolean = camera?.cameraInfo?.hasFlashUnit() ?: false

    fun supportsZoom(): Boolean {
        val zoomState = camera?.cameraInfo?.zoomState?.value
        return (zoomState?.maxZoomRatio ?: 1f) > 1f
    }

    suspend fun open(): OpenSessionResult {
        OpenCvScanEngine.init()
        close()
        val provider = getOrCreateProvider()

        val entry = textureRegistry.createSurfaceTexture()
        textureEntry = entry

        val preview = Preview.Builder().build()
        preview.setSurfaceProvider(mainExecutor) { request ->
            bindPreviewSurface(entry, request)
        }

        val analysisResolution = ResolutionSelector.Builder()
            .setResolutionStrategy(
                ResolutionStrategy(
                    Size(1280, 720),
                    ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER,
                ),
            )
            .build()
        val analysis = ImageAnalysis.Builder()
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .setResolutionSelector(analysisResolution)
            .build()
        val captureAnalyzer = CaptureAnalyzer { result ->
            lastAnalysis = result
            onFrameAnalysis?.invoke(result)
        }
        analyzer = captureAnalyzer
        analysis.setAnalyzer(analysisExecutor, captureAnalyzer)
        imageAnalysis = analysis

        val resolutionSelector = ResolutionSelector.Builder()
            .setResolutionStrategy(
                ResolutionStrategy(
                    Size(4032, 3024),
                    ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER,
                ),
            )
            .build()
        val capture = ImageCapture.Builder()
            .setCaptureMode(ImageCapture.CAPTURE_MODE_MAXIMIZE_QUALITY)
            .setResolutionSelector(resolutionSelector)
            .build()
        imageCapture = capture

        val rotation = if (lifecycleOwner is Activity) {
            lifecycleOwner.windowManager.defaultDisplay.rotation
        } else {
            Surface.ROTATION_0
        }
        preview.targetRotation = rotation
        analysis.targetRotation = rotation
        capture.targetRotation = rotation
        previewAspectRatio = 4.0 / 3.0

        provider.unbindAll()
        try {
            camera = provider.bindToLifecycle(
                lifecycleOwner,
                CameraSelector.DEFAULT_BACK_CAMERA,
                preview,
                analysis,
                capture,
            )
        } catch (e: Exception) {
            close()
            throw CaptureError.UnsupportedDevice(e.message ?: "Cannot bind camera")
        }

        val cam = camera
        if (cam != null) {
            val factory = SurfaceOrientedMeteringPointFactory(1f, 1f)
            val center = factory.createPoint(0.5f, 0.5f)
            cam.cameraControl.startFocusAndMetering(
                FocusMeteringAction.Builder(center, FocusMeteringAction.FLAG_AF or FocusMeteringAction.FLAG_AE)
                    .setAutoCancelDuration(4, TimeUnit.SECONDS)
                    .build(),
            )
        }

        return OpenSessionResult(entry.id(), previewAspectRatio)
    }

    private fun bindPreviewSurface(
        entry: TextureRegistry.SurfaceTextureEntry,
        request: SurfaceRequest,
    ) {
        val surfaceTexture = entry.surfaceTexture()
        surfaceTexture.setDefaultBufferSize(request.resolution.width, request.resolution.height)
        val surface = Surface(surfaceTexture)
        Log.i(
            TAG,
            "Providing preview SurfaceTexture ${request.resolution.width}x${request.resolution.height} " +
                "textureId=${entry.id()}",
        )
        request.provideSurface(surface, mainExecutor) {
            surface.release()
        }
    }

    private suspend fun getOrCreateProvider(): ProcessCameraProvider {
        cameraProvider?.let { return it }
        return suspendCoroutine { continuation ->
            val future = ProcessCameraProvider.getInstance(context)
            future.addListener({
                try {
                    val provider = future.get()
                    cameraProvider = provider
                    continuation.resume(provider)
                } catch (e: Exception) {
                    continuation.resumeWithException(CaptureError.UnsupportedDevice(e.message ?: "No camera available"))
                }
            }, mainExecutor)
        }
    }

    suspend fun captureStill(): StillCaptureResult {
        val capture = imageCapture ?: throw CaptureError.ProcessingFailed("Session not open")
        waitFor3a()
        shutterSound.play(MediaActionSound.SHUTTER_CLICK)
        val file = File(capturesDir, "${UUID.randomUUID()}.jpg")
        val options = ImageCapture.OutputFileOptions.Builder(file).build()

        suspendCoroutine<Unit> { continuation ->
            capture.takePicture(
                options,
                analysisExecutor,
                object : ImageCapture.OnImageSavedCallback {
                    override fun onImageSaved(outputResults: ImageCapture.OutputFileResults) {
                        continuation.resume(Unit)
                    }

                    override fun onError(exception: ImageCaptureException) {
                        continuation.resumeWithException(
                            CaptureError.ProcessingFailed(exception.message ?: "Capture failed"),
                        )
                    }
                },
            )
        }

        val detection = OpenCvScanEngine.detectFromPath(file.absolutePath)
        val stillScore = OpenCvScanEngine.scorePath(file.absolutePath)
        val warnings = mutableListOf<String>()
        if (stillScore < 0.12) warnings.add("blur")
        if (detection.quad == null) warnings.add("clippedEdges")
        return StillCaptureResult(
            originalImagePath = file.absolutePath,
            quad = detection.quad?.toArray(),
            qualityScore = stillScore,
            warnings = warnings,
            capturedAtMs = System.currentTimeMillis(),
            confidence = detection.quad?.confidence ?: 0.0,
            analyzedFromStill = true,
        )
    }

    private suspend fun waitFor3a(timeoutMs: Long = 700) {
        val start = System.currentTimeMillis()
        while (System.currentTimeMillis() - start < timeoutMs) {
            val a = lastAnalysis
            if (a != null && a.focusAcceptable && a.exposureAcceptable && a.motionBelowThreshold) {
                return
            }
            delay(40)
        }
    }

    fun setFlashMode(mode: String) {
        val capture = imageCapture ?: return
        when (mode) {
            "off" -> capture.flashMode = ImageCapture.FLASH_MODE_OFF
            "on" -> capture.flashMode = ImageCapture.FLASH_MODE_ON
            "auto" -> capture.flashMode = ImageCapture.FLASH_MODE_AUTO
            "torch" -> camera?.cameraControl?.enableTorch(true)
        }
        if (mode != "torch") {
            camera?.cameraControl?.enableTorch(false)
        }
    }

    fun setZoom(level: Float) {
        camera?.cameraControl?.setLinearZoom(level.coerceIn(0f, 1f))
    }

    fun setFocusAndExposurePoint(x: Float, y: Float) {
        val cam = camera ?: return
        val factory = SurfaceOrientedMeteringPointFactory(1f, 1f)
        val point = factory.createPoint(x, y)
        val action = FocusMeteringAction.Builder(
            point,
            FocusMeteringAction.FLAG_AF or FocusMeteringAction.FLAG_AE,
        ).build()
        cam.cameraControl.startFocusAndMetering(action)
    }

    fun close() {
        cameraProvider?.unbindAll()
        analyzer?.reset()
        analyzer = null
        imageAnalysis = null
        imageCapture = null
        camera = null
        textureEntry?.release()
        textureEntry = null
    }

    fun shutdown() {
        close()
        cameraProvider = null
        shutterSound.release()
    }
}
