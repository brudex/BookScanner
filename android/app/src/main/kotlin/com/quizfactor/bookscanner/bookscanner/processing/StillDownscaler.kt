package com.quizfactor.bookscanner.bookscanner.processing

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import java.io.File
import java.io.FileOutputStream
import kotlin.math.max

/**
 * Bounds a saved still so its long side is at most [maxLongSide] pixels.
 * The system document scanner returns 30-65 MP pages on some phones; every
 * later decode (review thumbnails, crop, filters, OCR) would otherwise need
 * 150-260 MB per page. Decodes with power-of-two subsampling so peak memory
 * stays near the output size, applies EXIF orientation (the re-encoded JPEG
 * carries no EXIF), and copies the file unchanged when it is already small.
 */
object StillDownscaler {
    data class Result(val width: Int, val height: Int, val downscaled: Boolean)

    fun downscale(sourcePath: String, outputPath: String, maxLongSide: Int, quality: Int = 92): Result {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(sourcePath, bounds)
        val srcW = bounds.outWidth
        val srcH = bounds.outHeight
        require(srcW > 0 && srcH > 0) { "Not a decodable image: $sourcePath" }

        val rotation = exifRotationDegrees(sourcePath)
        val longSide = max(srcW, srcH)
        if (longSide <= maxLongSide && rotation == 0) {
            if (sourcePath != outputPath) File(sourcePath).copyTo(File(outputPath), overwrite = true)
            return Result(srcW, srcH, downscaled = false)
        }

        var sample = 1
        while (longSide / (sample * 2) >= maxLongSide) sample *= 2
        val decoded = BitmapFactory.decodeFile(
            sourcePath,
            BitmapFactory.Options().apply { inSampleSize = sample },
        ) ?: error("Could not decode $sourcePath")

        val scale = minOf(1.0, maxLongSide.toDouble() / max(decoded.width, decoded.height))
        val matrix = Matrix().apply {
            if (scale < 1.0) postScale(scale.toFloat(), scale.toFloat())
            if (rotation != 0) postRotate(rotation.toFloat())
        }
        val out = Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, matrix, true)
        if (out !== decoded) decoded.recycle()

        val tmp = File("$outputPath.tmp")
        FileOutputStream(tmp).use { stream ->
            check(out.compress(Bitmap.CompressFormat.JPEG, quality, stream)) { "JPEG encode failed" }
        }
        val result = Result(out.width, out.height, downscaled = true)
        out.recycle()
        if (!tmp.renameTo(File(outputPath))) {
            tmp.copyTo(File(outputPath), overwrite = true)
            tmp.delete()
        }
        return result
    }

    private fun exifRotationDegrees(path: String): Int = try {
        when (ExifInterface(path).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
            ExifInterface.ORIENTATION_ROTATE_90 -> 90
            ExifInterface.ORIENTATION_ROTATE_180 -> 180
            ExifInterface.ORIENTATION_ROTATE_270 -> 270
            else -> 0
        }
    } catch (_: Exception) {
        0
    }
}
