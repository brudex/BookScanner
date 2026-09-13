package com.quizfactor.bookscanner.bookscanner.processing

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import org.opencv.android.OpenCVLoader
import org.opencv.android.Utils
import org.opencv.core.Core
import org.opencv.core.CvType
import org.opencv.core.Mat
import org.opencv.core.MatOfPoint
import org.opencv.core.MatOfPoint2f
import org.opencv.core.Point
import org.opencv.core.Size
import org.opencv.imgproc.Imgproc
import kotlin.math.max
import kotlin.math.min

/**
 * OpenCV 4.11 contour detector, perspective warp, and document filters.
 * Lives in the native processing package; Flutter only receives paths and
 * normalized geometry (SPEC 9.1 / BookScannerRevamp §5.4).
 */
object OpenCvScanEngine {
    const val OPENCV_VERSION = "4.11.0"
    const val LIVE_MAX_DIM = 720
    const val STILL_MAX_DIM = 1400

    @Volatile
    var available: Boolean = false
        private set

    fun init(): Boolean {
        if (available) return true
        available = OpenCVLoader.initLocal()
        return available
    }

    data class Detection(
        val quad: DetectedQuad?,
        val rejection: String? = null,
    )

    fun detectFromLuma(width: Int, height: Int, pixels: IntArray, maxDim: Int = LIVE_MAX_DIM): Detection {
        if (!init()) return Detection(null, "opencv_unavailable")
        val mat = Mat(height, width, CvType.CV_8UC1)
        val bytes = ByteArray(width * height)
        for (i in pixels.indices) bytes[i] = pixels[i].toByte()
        mat.put(0, 0, bytes)
        val result = detectMat(mat, maxDim)
        mat.release()
        return result
    }

    fun detectFromPath(path: String): Detection {
        if (!init()) return Detection(null, "opencv_unavailable")
        val opts = BitmapFactory.Options().apply { inSampleSize = 2 }
        val bitmap = BitmapFactory.decodeFile(path, opts) ?: return Detection(null, "decode_failed")
        val mat = Mat()
        Utils.bitmapToMat(bitmap, mat)
        bitmap.recycle()
        val gray = Mat()
        Imgproc.cvtColor(mat, gray, Imgproc.COLOR_RGBA2GRAY)
        mat.release()
        val result = detectMat(gray, STILL_MAX_DIM)
        gray.release()
        return result
    }

    fun scorePath(path: String): Double {
        if (!init()) return 0.0
        val opts = BitmapFactory.Options().apply { inSampleSize = 4 }
        val bitmap = BitmapFactory.decodeFile(path, opts) ?: return 0.0
        val mat = Mat()
        Utils.bitmapToMat(bitmap, mat)
        bitmap.recycle()
        val gray = Mat()
        Imgproc.cvtColor(mat, gray, Imgproc.COLOR_RGBA2GRAY)
        mat.release()
        val lap = Mat()
        Imgproc.Laplacian(gray, lap, CvType.CV_64F)
        gray.release()
        val mu = org.opencv.core.MatOfDouble()
        val sigma = org.opencv.core.MatOfDouble()
        Core.meanStdDev(lap, mu, sigma)
        lap.release()
        val v = sigma.toArray()[0]
        return ((v * v) / 900.0).coerceIn(0.0, 1.0)
    }

    fun warpAndEnhance(
        sourcePath: String,
        destPath: String,
        crop: DoubleArray?,
        detectCrop: Boolean,
        filter: String,
        removeShadows: Boolean,
    ): Pair<DoubleArray?, Double> {
        if (!init()) return Pair(null, 0.0)
        val bitmap = BitmapFactory.decodeFile(sourcePath) ?: return Pair(null, 0.0)
        val src = Mat()
        Utils.bitmapToMat(bitmap, src)
        bitmap.recycle()
        var applied = crop
        if (detectCrop) {
            val gray = Mat()
            Imgproc.cvtColor(src, gray, Imgproc.COLOR_RGBA2GRAY)
            val detected = detectMat(gray, STILL_MAX_DIM)
            gray.release()
            if (detected.quad != null) applied = detected.quad.toArray()
        }
        val cropped = applied != null && !OpenCvQuadMath.isNearlyFullFrame(arrayToPairs(applied))
        var page = if (cropped) warp(src, applied!!) else src
        if (cropped && removeShadows) {
            val norm = normalizeIllumination(page)
            if (page !== src) page.release()
            page = norm
        }
        val filtered = applyFilter(page, filter)
        if (page !== src && page !== filtered) page.release()
        val outBmp = Bitmap.createBitmap(filtered.cols(), filtered.rows(), Bitmap.Config.ARGB_8888)
        Utils.matToBitmap(filtered, outBmp)
        if (filtered !== src) filtered.release()
        src.release()
        java.io.FileOutputStream(destPath).use { outBmp.compress(Bitmap.CompressFormat.JPEG, 92, it) }
        outBmp.recycle()
        val score = scorePath(destPath)
        return Pair(if (cropped) applied else doubleArrayOf(0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0), score)
    }

    private fun arrayToPairs(a: DoubleArray) = listOf(
        a[0] to a[1], a[2] to a[3], a[4] to a[5], a[6] to a[7],
    )

    private fun detectMat(grayIn: Mat, maxDim: Int): Detection {
        var gray = grayIn
        val scale = maxDim.toDouble() / max(gray.cols(), gray.rows())
        if (scale < 1.0) {
            val resized = Mat()
            Imgproc.resize(gray, resized, Size(), scale, scale, Imgproc.INTER_AREA)
            if (gray !== grayIn) gray.release()
            gray = resized
        }
        Imgproc.GaussianBlur(gray, gray, Size(5.0, 5.0), 0.0)
        val median = Core.mean(gray).`val`[0]
        val lower = max(10.0, 0.66 * median)
        val upper = min(255.0, 1.33 * median * 1.5)
        val edges = Mat()
        Imgproc.Canny(gray, edges, lower, upper)
        val kernel = Imgproc.getStructuringElement(Imgproc.MORPH_RECT, Size(3.0, 3.0))
        Imgproc.morphologyEx(edges, edges, Imgproc.MORPH_CLOSE, kernel)
        val contours = ArrayList<MatOfPoint>()
        Imgproc.findContours(edges, contours, Mat(), Imgproc.RETR_LIST, Imgproc.CHAIN_APPROX_SIMPLE)
        edges.release()
        contours.sortByDescending { Imgproc.contourArea(it) }
        var bestScore = 0.0
        var bestPts: List<Pair<Double, Double>>? = null
        val w = gray.cols().toDouble()
        val h = gray.rows().toDouble()
        for (c in contours.take(12)) {
            val c2f = MatOfPoint2f(*c.toArray())
            val peri = Imgproc.arcLength(c2f, true)
            val approx = MatOfPoint2f()
            Imgproc.approxPolyDP(c2f, approx, 0.02 * peri, true)
            c2f.release()
            val pts = approx.toArray()
            approx.release()
            if (pts.size != 4) continue
            val norm = pts.map { (it.x / w) to (it.y / h) }
            val ordered = OpenCvQuadMath.orderCorners(norm)
            val score = OpenCvQuadMath.score(ordered)
            if (score > bestScore) {
                bestScore = score
                bestPts = ordered
            }
        }
        if (gray !== grayIn) gray.release()
        if (bestPts == null || bestScore < OpenCvQuadMath.MIN_CONFIDENCE) {
            return Detection(null, "low_confidence")
        }
        val q = bestPts
        return Detection(
            DetectedQuad(q[0].first, q[0].second, q[1].first, q[1].second, q[2].first, q[2].second, q[3].first, q[3].second, min(1.0, bestScore)),
        )
    }

    private fun warp(src: Mat, crop: DoubleArray): Mat {
        val w = src.cols().toDouble()
        val h = src.rows().toDouble()
        val srcPts = org.opencv.core.MatOfPoint2f(
            Point(crop[0] * w, crop[1] * h),
            Point(crop[2] * w, crop[3] * h),
            Point(crop[4] * w, crop[5] * h),
            Point(crop[6] * w, crop[7] * h),
        )
        fun dist(i: Int, j: Int): Double {
            val a = srcPts.toArray()[i]
            val b = srcPts.toArray()[j]
            val dx = a.x - b.x
            val dy = a.y - b.y
            return kotlin.math.sqrt(dx * dx + dy * dy)
        }
        val outW = ((dist(0, 1) + dist(3, 2)) / 2).toInt().coerceIn(1, 1 shl 16)
        val outH = ((dist(0, 3) + dist(1, 2)) / 2).toInt().coerceIn(1, 1 shl 16)
        val dstPts = MatOfPoint2f(
            Point(0.0, 0.0),
            Point((outW - 1).toDouble(), 0.0),
            Point((outW - 1).toDouble(), (outH - 1).toDouble()),
            Point(0.0, (outH - 1).toDouble()),
        )
        val m = Imgproc.getPerspectiveTransform(srcPts, dstPts)
        val out = Mat()
        Imgproc.warpPerspective(src, out, m, Size(outW.toDouble(), outH.toDouble()))
        srcPts.release()
        dstPts.release()
        m.release()
        return out
    }

    private fun normalizeIllumination(src: Mat): Mat {
        val small = Mat()
        val scale = 300.0 / src.cols()
        Imgproc.resize(src, small, Size(300.0, max(1.0, src.rows() * scale)))
        val blur = Mat()
        Imgproc.GaussianBlur(small, blur, Size(0.0, 0.0), 12.0)
        small.release()
        val bg = Mat()
        Imgproc.resize(blur, bg, src.size(), 0.0, 0.0, Imgproc.INTER_LINEAR)
        blur.release()
        val srcF = Mat()
        val bgF = Mat()
        src.convertTo(srcF, CvType.CV_32FC4)
        bg.convertTo(bgF, CvType.CV_32FC4)
        bg.release()
        Core.add(bgF, org.opencv.core.Scalar(1.0, 1.0, 1.0, 1.0), bgF)
        val outF = Mat()
        Core.divide(srcF, bgF, outF)
        srcF.release()
        bgF.release()
        Core.multiply(outF, org.opencv.core.Scalar(235.0, 235.0, 235.0, 255.0), outF)
        val out = Mat()
        outF.convertTo(out, CvType.CV_8UC4)
        outF.release()
        return out
    }

    private fun applyFilter(src: Mat, filter: String): Mat {
        return when (filter) {
            "enhancedColor" -> {
                val ycrcb = Mat()
                Imgproc.cvtColor(src, ycrcb, Imgproc.COLOR_RGBA2RGB)
                val y = Mat()
                Imgproc.cvtColor(ycrcb, y, Imgproc.COLOR_RGB2YCrCb)
                val ch = ArrayList<Mat>()
                Core.split(y, ch)
                val clahe = Imgproc.createCLAHE(2.0, Size(8.0, 8.0))
                clahe.apply(ch[0], ch[0])
                Core.merge(ch, y)
                val rgb = Mat()
                Imgproc.cvtColor(y, rgb, Imgproc.COLOR_YCrCb2RGB)
                val out = Mat()
                Imgproc.cvtColor(rgb, out, Imgproc.COLOR_RGB2RGBA)
                ycrcb.release()
                y.release()
                rgb.release()
                ch.forEach { it.release() }
                out
            }
            "grayscale" -> {
                val g = Mat()
                Imgproc.cvtColor(src, g, Imgproc.COLOR_RGBA2GRAY)
                val out = Mat()
                Imgproc.cvtColor(g, out, Imgproc.COLOR_GRAY2RGBA)
                g.release()
                out
            }
            "blackAndWhite" -> {
                val g = Mat()
                Imgproc.cvtColor(src, g, Imgproc.COLOR_RGBA2GRAY)
                val bw = Mat()
                Imgproc.adaptiveThreshold(
                    g,
                    bw,
                    255.0,
                    Imgproc.ADAPTIVE_THRESH_GAUSSIAN_C,
                    Imgproc.THRESH_BINARY,
                    15,
                    8.0,
                )
                val out = Mat()
                Imgproc.cvtColor(bw, out, Imgproc.COLOR_GRAY2RGBA)
                g.release()
                bw.release()
                out
            }
            "photo" -> {
                val out = Mat()
                src.convertTo(out, -1, 1.05, 4.0)
                out
            }
            else -> src
        }
    }
}
