package com.quizfactor.bookscanner.bookscanner.processing

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class OpenCvQuadMathTest {
    @Test
    fun ordersCornersTlTrBrBl() {
        val ordered = OpenCvQuadMath.orderCorners(
            listOf(0.9 to 0.1, 0.1 to 0.1, 0.9 to 0.9, 0.1 to 0.9),
        )
        assertEquals(0.1, ordered[0].first, 1e-9)
        assertEquals(0.1, ordered[0].second, 1e-9)
        assertEquals(0.9, ordered[1].first, 1e-9)
        assertEquals(0.9, ordered[2].first, 1e-9)
        assertEquals(0.1, ordered[3].first, 1e-9)
    }

    @Test
    fun rejectsNearlyFullFrame() {
        val score = OpenCvQuadMath.score(
            listOf(0.0 to 0.0, 1.0 to 0.0, 1.0 to 1.0, 0.0 to 1.0),
        )
        assertEquals(0.0, score, 1e-9)
    }

    @Test
    fun scoresInsetPageAboveThreshold() {
        val score = OpenCvQuadMath.score(
            listOf(0.12 to 0.10, 0.88 to 0.10, 0.88 to 0.90, 0.12 to 0.90),
        )
        assertTrue(score >= OpenCvQuadMath.MIN_CONFIDENCE)
    }

    @Test
    fun emaSmoothsTowardCurrent() {
        val prev = doubleArrayOf(0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0)
        val cur = doubleArrayOf(0.2, 0.2, 0.8, 0.2, 0.8, 0.8, 0.2, 0.8)
        val out = OpenCvQuadMath.ema(prev, cur, 0.5)
        assertEquals(0.1, out[0], 1e-9)
        assertEquals(0.9, out[2], 1e-9)
    }
}
