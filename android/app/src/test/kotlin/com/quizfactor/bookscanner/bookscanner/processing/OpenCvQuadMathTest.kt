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

    @Test
    fun convexHullDropsInteriorPoint() {
        val points = listOf(0.0 to 0.0, 1.0 to 0.0, 1.0 to 1.0, 0.0 to 1.0, 0.5 to 0.5)
        val hull = OpenCvQuadMath.convexHull(points)
        assertEquals(4, hull.size)
        assertTrue(hull.none { it == (0.5 to 0.5) })
    }

    @Test
    fun convexHullKeepsAllPointsOfABowedEdgeContour() {
        // A page whose top edge bows outward (curved book page, or a
        // glare break splitting one straight edge into two segments)
        // approximates to 6 points instead of a clean 4 -- the scenario
        // `OpenCvScanEngine.detectMat` previously discarded outright
        // because it required `approxPolyDP` to already land on exactly 4.
        val bowedTopEdge = listOf(
            0.0 to 0.05, 0.4 to 0.0, 0.6 to 0.0, 1.0 to 0.05,
            1.0 to 1.0, 0.0 to 1.0,
        )
        val hull = OpenCvQuadMath.convexHull(bowedTopEdge)
        assertEquals(6, hull.size)
    }

    @Test
    fun reduceToQuadReturnsUnchangedWhenAlreadyFourOrFewer() {
        val square = listOf(0.0 to 0.0, 1.0 to 0.0, 1.0 to 1.0, 0.0 to 1.0)
        assertEquals(square, OpenCvQuadMath.reduceToQuad(square))
    }

    @Test
    fun reduceToQuadDropsTheCheapestVertexOfACornerChamfer() {
        // A square with its top-right corner chamfered by glare/occlusion
        // (5 points). The chamfer contributes the least triangle area of
        // any vertex, so it -- not a real corner -- is what gets dropped.
        val pentagon = listOf(0.0 to 0.0, 8.0 to 0.0, 10.0 to 2.0, 10.0 to 10.0, 0.0 to 10.0)
        val quad = OpenCvQuadMath.reduceToQuad(pentagon)
        assertEquals(listOf(0.0 to 0.0, 10.0 to 2.0, 10.0 to 10.0, 0.0 to 10.0), quad)
    }

    @Test
    fun reduceToQuadCollapsesABowedEdgeHullToFourCorners() {
        val bowedTopEdge = listOf(
            0.0 to 0.05, 0.4 to 0.0, 0.6 to 0.0, 1.0 to 0.05,
            1.0 to 1.0, 0.0 to 1.0,
        )
        val quad = OpenCvQuadMath.reduceToQuad(bowedTopEdge)
        assertEquals(4, quad.size)
        // Every surviving point is one of the original hull vertices --
        // reduction only drops points, it never invents new ones.
        assertTrue(quad.all { it in bowedTopEdge })
    }
}
