package com.rekindle.app.core.render

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs
import kotlin.math.max

/**
 * The page curl's geometry, which the desktop client draws from the same
 * construction in Dart. Drawing needs a canvas; the paper's whereabouts do not.
 */
class PageCurlGeometryTest {
    private val width = 320f

    /** Left to right: hinged at 0, reaching right. */
    private fun ltr(progress: Float) = PageCurl.layout(0f, 1, width, progress)

    /** Right to left, as manga reads: hinged at the right edge, reaching left. */
    private fun rtl(progress: Float) = PageCurl.layout(width, -1, width, progress)

    @Test
    fun `a flat or fully turned page has nothing to draw`() {
        assertNull(ltr(0f))
        assertNull(ltr(1f))
        assertNull(ltr(-0.2f))
        assertNull(ltr(1.5f))
        assertNull(PageCurl.layout(0f, 1, 0f, 0.5f))
    }

    @Test
    fun `at the start of a turn the sheet still covers the whole page`() {
        val curl = requireNotNull(ltr(0.001f))
        assertEquals(0f, curl.flatLeft, 0.01f)
        // The flat part runs almost to the free edge; what is left is the roll.
        assertTrue("flat ${curl.flatRight}", curl.flatRight > width - 1f)
        assertTrue("covers the page", sheetRight(curl) > width - 1f)
    }

    @Test
    fun `at the end of a turn the sheet has left the page`() {
        val curl = requireNotNull(ltr(0.999f))
        assertTrue("flat ${curl.flatRight}", curl.flatRight < 1f)
        // Everything else has turned over past the spine, off the page.
        assertTrue("sheet ${sheetRight(curl)}", sheetRight(curl) < 2f)
    }

    @Test
    fun `the fold sweeps from the free edge to the spine`() {
        var last = Float.MAX_VALUE
        for (step in 1..19) {
            val curl = requireNotNull(ltr(step / 20f))
            assertTrue("fold went back at $step", curl.flatRight < last)
            last = curl.flatRight
        }
    }

    @Test
    fun `strips tile the rolled part without gaps`() {
        val curl = requireNotNull(ltr(0.5f))
        val strips = curl.strips
        assertTrue("some strips", strips.size > 50)
        // Printed order: each strip is printed just past the one before it.
        for (i in 1 until strips.size) {
            val gap = strips[i].srcLeft - strips[i - 1].srcRight
            assertTrue("gap of $gap in the printing at $i", abs(gap) < 1f)
        }
        // The first strip is printed where the flat part leaves off.
        assertTrue(abs(strips.first().srcLeft - curl.flatRight) < 1f)
        // The last is printed at the page's free edge.
        assertTrue(abs(strips.last().srcRight - width) < 1f)
    }

    @Test
    fun `the roll turns the paper over halfway along`() {
        val curl = requireNotNull(ltr(0.5f))
        val turned = curl.strips.map { it.turned }
        // Face up first, then over: one changeover, never alternating.
        assertEquals(1, turned.zipWithNext().count { (a, b) -> a != b })
        assertTrue("starts face up", !turned.first())
        assertTrue("ends turned over", turned.last())
    }

    @Test
    fun `paper on the roll is squeezed, never stretched`() {
        val curl = requireNotNull(ltr(0.5f))
        for (s in curl.strips) {
            val printed = s.srcRight - s.srcLeft
            val shown = (s.dstRight - s.dstLeft) - 1f // less the half-pixel overlap
            assertTrue("stretched: $printed printed, $shown shown", shown <= printed + 0.1f)
        }
    }

    @Test
    fun `shading is strongest where the paper faces furthest from the light`() {
        val curl = requireNotNull(ltr(0.5f))
        val fronts = curl.strips.filter { !it.turned }
        // The flat end is unshaded; it darkens as it rolls away.
        assertEquals(0f, fronts.first().shade, 0.01f)
        assertTrue(fronts.last().shade > fronts.first().shade)
        for (s in curl.strips) assertTrue("shade ${s.shade}", s.shade in 0f..0.6f)
    }

    @Test
    fun `the roll casts its shadow onto the page beyond it`() {
        val curl = requireNotNull(ltr(0.5f))
        assertTrue("shadow at ${curl.shadowEdge}", curl.shadowEdge > curl.flatRight)
        assertTrue(curl.shadowStrength > 0f)
        // Strongest mid-turn, fading at either end.
        assertTrue(curl.shadowStrength > requireNotNull(ltr(0.05f)).shadowStrength)
        assertTrue(curl.shadowStrength > requireNotNull(ltr(0.95f)).shadowStrength)
    }

    @Test
    fun `turning right to left is the mirror of turning left to right`() {
        for (step in 1..9) {
            val t = step / 10f
            val a = requireNotNull(ltr(t))
            val b = requireNotNull(rtl(t))
            assertEquals("flat edge at $t", width - a.flatRight, b.flatLeft, 0.01f)
            assertEquals("shadow at $t", width - a.shadowEdge, b.shadowEdge, 0.01f)
            assertEquals("strips at $t", a.strips.size, b.strips.size)
            for (i in a.strips.indices) {
                val l = a.strips[i]
                val r = b.strips[i]
                assertEquals("src at $t/$i", width - l.srcRight, r.srcLeft, 0.01f)
                assertEquals("dst at $t/$i", width - l.dstRight, r.dstLeft, 0.01f)
                assertEquals("shade at $t/$i", l.shade, r.shade, 0.0001f)
                assertEquals("face at $t/$i", l.turned, r.turned)
            }
        }
    }

    /**
     * The desktop client draws the same curl from the same construction in
     * Dart, and that is the one that has been looked at. These are its numbers
     * for a 100-pixel page half way through a turn, worked out from
     * `page_curl.dart` by hand, so a slip in the translation shows up here.
     */
    @Test
    fun `the paper lands where the desktop client puts it`() {
        val curl = requireNotNull(PageCurl.layout(0f, 1, 100f, 0.5f))
        assertEquals(50f, curl.flatRight, 0.0005f)
        assertEquals(58f, curl.shadowEdge, 0.0005f)
        assertEquals(0.22f, curl.shadowStrength, 0.0005f)
        assertEquals(120, curl.strips.size)
        assertEquals(30, curl.strips.count { !it.turned })

        val expected = listOf(
            // index to src, dst and shade
            Triple(0, listOf(50f, 50.416667f), listOf(49.5f, 50.916478f)) to (0.000102f to false),
            Triple(60, listOf(75f, 75.416667f), listOf(49.216075f, 50.632735f)) to (0.020003f to true),
            Triple(119, listOf(99.583333f, 100f), listOf(24.632741f, 26.049408f)) to (0.02f to true),
        )
        for ((where, face) in expected) {
            val (i, src, dst) = where
            val (shade, turned) = face
            val s = curl.strips[i]
            assertEquals("srcLeft at $i", src[0], s.srcLeft, 0.0005f)
            assertEquals("srcRight at $i", src[1], s.srcRight, 0.0005f)
            assertEquals("dstLeft at $i", dst[0], s.dstLeft, 0.0005f)
            assertEquals("dstRight at $i", dst[1], s.dstRight, 0.0005f)
            assertEquals("shade at $i", shade, s.shade, 0.0005f)
            assertEquals("face at $i", turned, s.turned)
        }
    }

    @Test
    fun `the back of the sheet is printed across the spine from its front`() {
        // A spread's sheet is the half-page on one side of a centre spine.
        val spine = 160f
        val curl = requireNotNull(PageCurl.layout(spine, 1, spine, 0.5f))
        for (s in curl.strips) {
            // Whatever is printed at a distance from the spine on the front is
            // printed the same distance the other way on the back, which is
            // where that paper lands once the sheet has turned right over.
            assertEquals(
                "mirrored about the spine",
                s.srcLeft - spine,
                spine - s.backSrcRight,
                0.001f,
            )
            assertEquals(
                "same width as the front band",
                s.srcRight - s.srcLeft,
                s.backSrcRight - s.backSrcLeft,
                0.001f,
            )
            // It lands on the other side of the spine, where the facing page
            // of the slide being turned to is.
            assertTrue("back at ${s.backSrcLeft}", s.backSrcLeft <= spine)
        }
        // Only the paper that has turned over carries the back, so it covers
        // more of the half-page as the turn goes on, reaching the spine as the
        // sheet lands.
        fun backReach(progress: Float) = requireNotNull(
            PageCurl.layout(spine, 1, spine, progress),
        ).strips.filter { it.turned }.maxOf { it.backSrcRight }
        assertTrue(backReach(0.5f) > 0f)
        assertTrue(backReach(0.8f) > backReach(0.5f))
        assertTrue("lands at the spine", backReach(0.95f) > spine - 15f)
    }

    @Test
    fun `a spread turns the half-page on the side the reader turns from`() {
        val spine = 160f
        val ltr = requireNotNull(PageCurl.layout(spine, 1, spine, 0.4f))
        val rtl = requireNotNull(PageCurl.layout(spine, -1, spine, 0.4f))
        // Left to right the sheet is the right half, and its back lands left.
        assertTrue(ltr.strips.all { it.srcLeft >= spine - 0.6f })
        assertTrue(ltr.strips.all { it.backSrcRight <= spine + 0.6f })
        // Right to left is the mirror of it.
        assertTrue(rtl.strips.all { it.srcRight <= spine + 0.6f })
        assertTrue(rtl.strips.all { it.backSrcLeft >= spine - 0.6f })
    }

    /** The far edge of the paper that is still on the page, left to right. */
    private fun sheetRight(curl: PageCurl.Layout): Float =
        curl.strips.fold(curl.flatRight) { far, s -> max(far, s.dstRight) }
}
