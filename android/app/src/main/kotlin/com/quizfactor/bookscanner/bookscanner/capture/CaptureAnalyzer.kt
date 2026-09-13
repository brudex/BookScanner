package com.quizfactor.bookscanner.bookscanner.capture

import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import com.quizfactor.bookscanner.bookscanner.processing.OpenCvQuadMath
import com.quizfactor.bookscanner.bookscanner.processing.OpenCvScanEngine

/**
 * ImageAnalysis.Analyzer for live-guidance frames. Uses OpenCV contour
 * detection when the engine initialized; sharpness/exposure/motion still
 * come from the downsampled luma buffer. Always closes [ImageProxy].
 */
class CaptureAnalyzer(
    private val onResult: (FrameAnalysisResult) -> Unit,
) : ImageAnalysis.Analyzer {

    private var previousFrame: LumaFrame? = null
    private var smoothedQuad: DoubleArray? = null
    private var stableSince: Long = 0L
    private var lastEmittedQuad: DoubleArray? = null
    private var lastAcceptableAt: Long = 0L

    companion object {
        private const val STABILITY_EPSILON = 0.018
        private const val STABILITY_DWELL_MS = 280L
        private const val MOTION_THRESHOLD = 6.0
        private const val SHARPNESS_THRESHOLD = 60.0
        private const val DARK_THRESHOLD = 40.0
        private const val BRIGHT_THRESHOLD = 235.0
    }

    override fun analyze(imageProxy: ImageProxy) {
        try {
            val image = imageProxy.image ?: return
            val frame = FrameMath.extractLuma(image)

            val detection = OpenCvScanEngine.detectFromLuma(frame.width, frame.height, frame.pixels)
            var quad = detection.quad?.toArray()
            val confidence = detection.quad?.confidence ?: 0.0
            if (quad != null) {
                smoothedQuad = OpenCvQuadMath.ema(smoothedQuad, quad)
                quad = smoothedQuad
            } else {
                smoothedQuad = null
            }

            val sharpnessScore = FrameMath.sharpness(frame)
            val avgLuma = FrameMath.averageLuminance(frame)
            val motion = FrameMath.motionScore(previousFrame, frame)
            previousFrame = frame

            val cornersStable = quadStability(quad)
            val focusAcceptable = sharpnessScore >= SHARPNESS_THRESHOLD
            val exposureAcceptable = avgLuma in DARK_THRESHOLD..BRIGHT_THRESHOLD
            val motionBelowThreshold = motion < MOTION_THRESHOLD
            if (focusAcceptable && exposureAcceptable && motionBelowThreshold) {
                lastAcceptableAt = System.currentTimeMillis()
            }

            val warnings = mutableListOf<String>()
            if (!focusAcceptable) warnings.add("blur")
            if (avgLuma < DARK_THRESHOLD) warnings.add("lowLight")
            if (avgLuma > BRIGHT_THRESHOLD) warnings.add("glare")
            if (quad == null) warnings.add("clippedEdges")

            val qualityScore = (sharpnessScore / 900.0).coerceIn(0.0, 1.0)
            onResult(
                FrameAnalysisResult(
                    timestampMs = System.currentTimeMillis(),
                    documentDetected = quad != null,
                    quad = quad,
                    cornersStable = cornersStable,
                    motionBelowThreshold = motionBelowThreshold,
                    focusAcceptable = focusAcceptable,
                    exposureAcceptable = exposureAcceptable,
                    warnings = warnings,
                    qualityScore = qualityScore,
                    confidence = confidence,
                ),
            )
        } finally {
            imageProxy.close()
        }
    }

    private fun quadStability(quad: DoubleArray?): Boolean {
        val previous = lastEmittedQuad
        lastEmittedQuad = quad
        if (quad == null) {
            stableSince = 0L
            return false
        }
        if (previous == null || OpenCvQuadMath.maxDelta(previous, quad) > STABILITY_EPSILON) {
            stableSince = System.currentTimeMillis()
            return false
        }
        return System.currentTimeMillis() - stableSince >= STABILITY_DWELL_MS
    }

    fun reset() {
        previousFrame = null
        smoothedQuad = null
        lastEmittedQuad = null
        stableSince = 0L
    }

    fun recentlyAcceptable(windowMs: Long = 400): Boolean =
        System.currentTimeMillis() - lastAcceptableAt <= windowMs
}

data class FrameAnalysisResult(
    val timestampMs: Long,
    val documentDetected: Boolean,
    val quad: DoubleArray?,
    val cornersStable: Boolean,
    val motionBelowThreshold: Boolean,
    val focusAcceptable: Boolean,
    val exposureAcceptable: Boolean,
    val warnings: List<String>,
    val qualityScore: Double,
    val confidence: Double = 0.0,
)
