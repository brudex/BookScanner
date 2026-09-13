package com.quizfactor.bookscanner.bookscanner.processing

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/** Normalized page quad + score. Pure Kotlin so JVM tests do not need OpenCV .so. */
data class DetectedQuad(
    val tlX: Double,
    val tlY: Double,
    val trX: Double,
    val trY: Double,
    val brX: Double,
    val brY: Double,
    val blX: Double,
    val blY: Double,
    val confidence: Double,
) {
    fun toArray(): DoubleArray = doubleArrayOf(tlX, tlY, trX, trY, brX, brY, blX, blY)
}

object OpenCvQuadMath {
    const val MIN_CONFIDENCE = 0.45
    const val ALGORITHM_VERSION = "1.0.0"

    fun orderCorners(pts: List<Pair<Double, Double>>): List<Pair<Double, Double>> {
        var tl = pts[0]
        var tr = pts[0]
        var br = pts[0]
        var bl = pts[0]
        var minSum = Double.POSITIVE_INFINITY
        var maxSum = Double.NEGATIVE_INFINITY
        var minDiff = Double.POSITIVE_INFINITY
        var maxDiff = Double.NEGATIVE_INFINITY
        for (p in pts) {
            val sum = p.first + p.second
            val diff = p.first - p.second
            if (sum < minSum) {
                minSum = sum
                tl = p
            }
            if (sum > maxSum) {
                maxSum = sum
                br = p
            }
            if (diff > maxDiff) {
                maxDiff = diff
                tr = p
            }
            if (diff < minDiff) {
                minDiff = diff
                bl = p
            }
        }
        return listOf(tl, tr, br, bl)
    }

    fun area(q: List<Pair<Double, Double>>): Double {
        var sum = 0.0
        for (i in q.indices) {
            val a = q[i]
            val b = q[(i + 1) % q.size]
            sum += a.first * b.second - b.first * a.second
        }
        return abs(sum) / 2.0
    }

    fun isNearlyFullFrame(q: List<Pair<Double, Double>>): Boolean =
        q[0].first < 0.03 && q[0].second < 0.03 &&
            q[1].first > 0.97 && q[1].second < 0.03 &&
            q[2].first > 0.97 && q[2].second > 0.97 &&
            q[3].first < 0.03 && q[3].second > 0.97

    fun score(q: List<Pair<Double, Double>>): Double {
        val area = area(q)
        if (area < 0.12 || area > 0.96) return 0.0
        if (isNearlyFullFrame(q)) return 0.0
        val cx = (q[0].first + q[1].first + q[2].first + q[3].first) / 4.0 - 0.5
        val cy = (q[0].second + q[1].second + q[2].second + q[3].second) / 4.0 - 0.5
        val center = (1.0 - 2.0 * sqrt(cx * cx + cy * cy)).coerceIn(0.15, 1.0)
        fun d(a: Pair<Double, Double>, b: Pair<Double, Double>) =
            sqrt((a.first - b.first) * (a.first - b.first) + (a.second - b.second) * (a.second - b.second))
        val top = d(q[0], q[1])
        val bot = d(q[3], q[2])
        val left = d(q[0], q[3])
        val right = d(q[1], q[2])
        val aspect = min(top, bot) / max(top, bot).coerceAtLeast(1e-6)
        val sides = min(left, right) / max(left, right).coerceAtLeast(1e-6)
        return area * center * aspect * sides
    }

    fun ema(previous: DoubleArray?, current: DoubleArray, alpha: Double = 0.35): DoubleArray {
        if (previous == null || previous.size != current.size) return current
        return DoubleArray(current.size) { i -> previous[i] * (1 - alpha) + current[i] * alpha }
    }

    fun maxDelta(a: DoubleArray, b: DoubleArray): Double {
        var m = 0.0
        for (i in a.indices) m = max(m, abs(a[i] - b[i]))
        return m
    }
}
