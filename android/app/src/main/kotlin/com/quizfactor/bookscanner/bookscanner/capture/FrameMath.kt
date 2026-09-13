package com.quizfactor.bookscanner.bookscanner.capture

import android.graphics.Bitmap
import android.media.Image
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/** A small downsampled grayscale buffer used for all live-analysis math. */
class LumaFrame(val width: Int, val height: Int, val pixels: IntArray)

/**
 * Classical, on-device frame analysis (SPEC 9.3: "fast classical pipeline
 * for flat documents: luminance conversion, contour/line candidates,
 * quadrilateral scoring... blur/exposure metrics"). Mirrors the Dart
 * fallback detector in `dart_page_detection_provider.dart` so behavior is
 * consistent whichever path runs, and is intentionally cheap: it must run
 * at live-preview frame rate on a downsampled buffer.
 */
object FrameMath {
    private const val TARGET_DIM = 480

    /** Extracts a downsampled grayscale buffer from a YUV_420_888 Y plane. */
    fun extractLuma(image: Image): LumaFrame {
        val yPlane = image.planes[0]
        val buffer = yPlane.buffer
        val rowStride = yPlane.rowStride
        val pixelStride = yPlane.pixelStride
        val srcWidth = image.width
        val srcHeight = image.height

        val scale = TARGET_DIM.toDouble() / max(srcWidth, srcHeight)
        val dstWidth = max(1, (srcWidth * scale).toInt())
        val dstHeight = max(1, (srcHeight * scale).toInt())

        val bytes = ByteArray(buffer.remaining())
        buffer.get(bytes)

        val pixels = IntArray(dstWidth * dstHeight)
        for (dy in 0 until dstHeight) {
            val sy = min(srcHeight - 1, (dy / scale).toInt())
            for (dx in 0 until dstWidth) {
                val sx = min(srcWidth - 1, (dx / scale).toInt())
                val index = sy * rowStride + sx * pixelStride
                val value = if (index < bytes.size) bytes[index].toInt() and 0xFF else 0
                pixels[dy * dstWidth + dx] = value
            }
        }
        return LumaFrame(dstWidth, dstHeight, pixels)
    }

    /** Same extraction path for an already-decoded bitmap (saved stills). */
    fun extractLuma(bitmap: Bitmap): LumaFrame {
        val scale = TARGET_DIM.toDouble() / max(bitmap.width, bitmap.height)
        val dstWidth = max(1, (bitmap.width * scale).toInt())
        val dstHeight = max(1, (bitmap.height * scale).toInt())
        val scaled = Bitmap.createScaledBitmap(bitmap, dstWidth, dstHeight, true)
        val pixels = IntArray(dstWidth * dstHeight)
        scaled.getPixels(pixels, 0, dstWidth, 0, 0, dstWidth, dstHeight)
        val luma = IntArray(dstWidth * dstHeight)
        for (i in pixels.indices) {
            val p = pixels[i]
            val r = (p shr 16) and 0xFF
            val g = (p shr 8) and 0xFF
            val b = p and 0xFF
            luma[i] = (0.299 * r + 0.587 * g + 0.114 * b).toInt()
        }
        if (scaled !== bitmap) scaled.recycle()
        return LumaFrame(dstWidth, dstHeight, luma)
    }

    fun averageLuminance(frame: LumaFrame): Double =
        frame.pixels.sumOf { it } / frame.pixels.size.toDouble()

    /**
     * Laplacian-variance sharpness estimate: higher variance means more
     * high-frequency detail (in focus); low variance means blur. Same
     * technique as the Dart baseline enhancement adapter, for consistent
     * "in focus" thresholds across platforms.
     */
    fun sharpness(frame: LumaFrame): Double {
        val w = frame.width
        val h = frame.height
        if (w < 3 || h < 3) return 0.0
        var sum = 0.0
        var sumSq = 0.0
        var count = 0
        for (y in 1 until h - 1) {
            for (x in 1 until w - 1) {
                val c = frame.pixels[y * w + x]
                val l = frame.pixels[y * w + x - 1]
                val r = frame.pixels[y * w + x + 1]
                val t = frame.pixels[(y - 1) * w + x]
                val b = frame.pixels[(y + 1) * w + x]
                val lap = (4 * c - l - r - t - b).toDouble()
                sum += lap
                sumSq += lap * lap
                count++
            }
        }
        if (count == 0) return 0.0
        val mean = sum / count
        return sumSq / count - mean * mean
    }

    /**
     * Estimates a document quadrilateral via row/column edge-energy
     * projection profiles (same approach as the Dart classical baseline).
     * Returns normalized (0..1) corner coordinates, or null if the edge
     * signal is too weak to trust.
     */
    fun detectQuad(frame: LumaFrame): DoubleArray? {
        val w = frame.width
        val h = frame.height
        if (w < 8 || h < 8) return null

        val rowEnergy = DoubleArray(h)
        val colEnergy = DoubleArray(w)
        for (y in 1 until h - 1) {
            for (x in 1 until w - 1) {
                val gx = abs(frame.pixels[y * w + x + 1] - frame.pixels[y * w + x - 1])
                val gy = abs(frame.pixels[(y + 1) * w + x] - frame.pixels[(y - 1) * w + x])
                val mag = (gx + gy).toDouble()
                rowEnergy[y] += mag
                colEnergy[x] += mag
            }
        }

        // 20%-of-peak (not 35%): a dense line of text inside the page
        // routinely has stronger Sobel-style energy than the true paper-to-
        // background boundary, so a high relative threshold walks the scan
        // past the real edge and stops at the first text line instead --
        // observed on-device as page edges being cropped into real content.
        val rowThreshold = (rowEnergy.maxOrNull() ?: 0.0) * 0.2
        val colThreshold = (colEnergy.maxOrNull() ?: 0.0) * 0.2

        var top = 0
        while (top < h - 1 && rowEnergy[top] < rowThreshold) top++
        var bottom = h - 1
        while (bottom > 0 && rowEnergy[bottom] < rowThreshold) bottom--
        var left = 0
        while (left < w - 1 && colEnergy[left] < colThreshold) left++
        var right = w - 1
        while (right > 0 && colEnergy[right] < colThreshold) right--

        if (right - left < w * 0.3 || bottom - top < h * 0.3) return null

        // Safety margin: bias toward keeping slightly more of the frame
        // rather than cutting into content, since a too-tight crop loses
        // pixels the user can't get back without a manual re-crop, while a
        // too-loose one just leaves a bit of background they can trim.
        val marginX = w * 0.03
        val marginY = h * 0.03
        val l = ((left - marginX) / w).coerceIn(0.0, 1.0)
        val r = ((right + marginX) / w).coerceIn(0.0, 1.0)
        val t = ((top - marginY) / h).coerceIn(0.0, 1.0)
        val b = ((bottom + marginY) / h).coerceIn(0.0, 1.0)
        // topLeft, topRight, bottomRight, bottomLeft — 8 doubles (x,y pairs).
        return doubleArrayOf(l, t, r, t, r, b, l, b)
    }

    /** Mean absolute per-pixel luminance delta between two same-size frames. */
    fun motionScore(previous: LumaFrame?, current: LumaFrame): Double {
        if (previous == null || previous.width != current.width || previous.height != current.height) {
            return 0.0
        }
        var sum = 0.0
        for (i in current.pixels.indices) {
            sum += abs(current.pixels[i] - previous.pixels[i])
        }
        return sum / current.pixels.size
    }
}
