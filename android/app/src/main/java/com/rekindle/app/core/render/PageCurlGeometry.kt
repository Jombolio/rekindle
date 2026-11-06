package com.rekindle.app.core.render

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * Where the paper of a curling page lies, part way through a turn.
 *
 * The page is hinged at [PageCurl.layout]'s `spine` and reaches `width` from it,
 * towards `direction` (1: to the right, -1: to the left). A fold sweeps from the
 * free edge to the spine as `progress` goes from 0 to 1. Beyond the fold the
 * page wraps round a roll that tightens as it goes, then lies flat again, folded
 * back over itself and showing its back. At 1 the whole page has turned over
 * onto the other side of the spine.
 *
 * This is geometry only, in the page's own pixels, so it can be checked without
 * drawing anything. [com.rekindle.app.ui.screens.drawPageCurl] paints it, and
 * the desktop client's `PageCurlPainter` is the same construction in Dart.
 */
object PageCurl {
    /** Vertical slices the rolled part is drawn in. */
    const val STRIPS = 120

    /** The roll's radius at the start of a turn, as a share of the page. */
    const val ROLL = 0.16f

    /** How far the roll's shadow reaches across the page beneath, in pixels. */
    const val SHADOW_REACH = 36f

    /**
     * One slice of paper: the band of the page it is printed on, and the band of
     * screen it now covers. Both are left-to-right, whichever way the page turns.
     */
    data class Strip(
        val srcLeft: Float,
        val srcRight: Float,
        /**
         * The band of the page printed on the sheet's *back*, which in a
         * spread is the facing page of the slide being turned to. It lands
         * across the spine from the front's, so it is the front's band
         * mirrored about the spine.
         */
        val backSrcLeft: Float,
        val backSrcRight: Float,
        val dstLeft: Float,
        val dstRight: Float,
        /** How far to darken it, 0 to 1, for facing away from the light. */
        val shade: Float,
        /** Past the top of the roll: this slice has its back to the reader. */
        val turned: Boolean,
    )

    data class Layout(
        /** The part still lying flat against the page, printed side up. */
        val flatLeft: Float,
        val flatRight: Float,
        val strips: List<Strip>,
        /** The roll's outer edge, where its shadow falls on the page beneath. */
        val shadowEdge: Float,
        val shadowStrength: Float,
    )

    /**
     * The paper's whereabouts at [progress], or null when the page is flat
     * against the spine (0) or has turned right over (1) and there is nothing
     * to draw over the page the pager is already showing.
     */
    fun layout(
        spine: Float,
        direction: Int,
        width: Float,
        progress: Float,
        strips: Int = STRIPS,
    ): Layout? {
        if (width <= 0f || progress <= 0f || progress >= 1f) return null
        val t = progress

        // The fold moves from the free edge to the spine; the roll tightens as
        // it goes, so the page lies flat at the end.
        val fold = width * (1f - t)
        val radius = width * ROLL * (1f - t)
        val halfTurn = (PI * radius).toFloat()
        if (radius <= 0f) return null

        fun screen(d: Float) = spine + direction * d

        // Where paper at distance [u] from the spine ends up, as a distance from
        // the spine, and the angle it has rolled through.
        fun place(u: Float): Pair<Float, Float> {
            val s = u - fold
            if (s <= 0f) return u to 0f
            val angle = s / radius
            if (angle <= PI) return (fold + radius * sin(angle)) to angle
            return (fold - (s - halfTurn)) to PI.toFloat()
        }

        val flatEdge = screen(fold)
        val out = ArrayList<Strip>(strips)
        for (i in 0 until strips) {
            val ua = fold + (width - fold) * i / strips
            val ub = fold + (width - fold) * (i + 1) / strips
            val (pa, aa) = place(ua)
            val (pb, ab) = place(ub)
            val angle = (aa + ab) / 2f
            val xa = screen(pa)
            val xb = screen(pb)
            // Half a pixel of overlap hides the joins between strips.
            val dstLeft = min(xa, xb) - 0.5f
            val dstRight = max(xa, xb) + 0.5f
            if (dstRight - dstLeft <= 0.6f) continue
            val sa = screen(ua)
            val sb = screen(ub)
            val ba = spine - direction * ua
            val bb = spine - direction * ub
            out += if (angle <= PI / 2f) {
                // The printed side, still facing up, darker as it turns away.
                Strip(
                    srcLeft = min(sa, sb),
                    srcRight = max(sa, sb),
                    backSrcLeft = min(ba, bb),
                    backSrcRight = max(ba, bb),
                    dstLeft = dstLeft,
                    dstRight = dstRight,
                    shade = 0.3f * (1f - cos(angle)),
                    turned = false,
                )
            } else {
                // The back, now facing up. With a page printed there it is
                // that page; otherwise the front showing faintly through,
                // reversed. Lit at the top of the roll, settling as it lies
                // flat.
                Strip(
                    srcLeft = min(sa, sb),
                    srcRight = max(sa, sb),
                    backSrcLeft = min(ba, bb),
                    backSrcRight = max(ba, bb),
                    dstLeft = dstLeft,
                    dstRight = dstRight,
                    shade = (0.16f * (1f + cos(angle)) + 0.04f) * (1f - t),
                    turned = true,
                )
            }
        }

        return Layout(
            flatLeft = min(spine, flatEdge),
            flatRight = max(spine, flatEdge),
            strips = out,
            shadowEdge = screen(fold + radius),
            shadowStrength = 0.22f * sin((PI * t).toFloat()),
        )
    }
}
