package com.rekindle.app.ui.screens

import android.graphics.Bitmap
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.unit.IntSize
import com.rekindle.app.core.render.PageCurl
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlin.math.roundToInt

/** The reader's own background, behind every slide. */
val ReaderBackdrop = Color.Black

/**
 * The back of a sheet, seen where it has folded over mid-turn. A shade up from
 * [ReaderBackdrop], so a turning page reads as paper lifting off the page
 * beneath rather than as a hole cut in it.
 */
val ReaderPaper = Color(0xFF2B2B2B)

/**
 * The page the reader is turning, curling over the slide beneath it.
 *
 * Drawn above the pager, so the sheet lies over the slide being turned to
 * rather than under it — the pager draws slides in index order, which would put
 * the next one on top. The sheet that turns is always the lower-numbered slide
 * of the pair the pager sits between, which makes one motion serve both
 * directions: at a progress of 0 it lies flat over the next slide, and at 1 it
 * has turned right over. Forwards runs that 0 to 1 and back runs it 1 to 0, and
 * because progress is read straight off the pager, a drag curls the sheet under
 * the reader's finger.
 *
 * [page] is the pager's continuous position in slides, read in the draw phase so
 * scrolling never costs a recomposition. [slide] draws one slide at the size it
 * is printed, so the sheet is the page and not the window around it.
 * [spreadAt] says whether a slide turns about the spine down its middle: true
 * for one two pages wide, whatever follows it. [backSlide] draws a slide as the
 * pager lays it out, filling the viewport: a spread prints the next slide on
 * the back of its turning half, and taking it from the pager's layout puts each
 * part where it will lie, however the two slides differ in size. [paper] is the
 * back of a sheet bound at its outer edge, where nothing is printed.
 */
@Composable
fun ComicPageCurl(
    page: () -> Float,
    reverse: Boolean,
    slideCount: Int,
    spreadAt: (leaf: Int) -> Boolean,
    slide: @Composable (index: Int) -> Unit,
    backSlide: @Composable (index: Int) -> Unit,
    paper: Color = ReaderPaper,
) {
    if (slideCount < 2) return
    val frontLayer = rememberGraphicsLayer()
    val backLayer = rememberGraphicsLayer()
    val last = slideCount - 2
    // The slide being turned, kept composed and recorded even at rest, so its
    // picture is ready the moment a turn starts.
    var leaf by remember { mutableIntStateOf(page().toInt().coerceIn(0, last)) }
    var sheet by remember { mutableStateOf<ImageBitmap?>(null) }
    var backSheet by remember { mutableStateOf<ImageBitmap?>(null) }
    // The size the sheet was last recorded at, reported from the draw phase.
    var recorded by remember { mutableStateOf(IntSize.Zero) }
    // The viewport the sheet is centred in.
    var viewport by remember { mutableStateOf(IntSize.Zero) }
    val spread = spreadAt(leaf)

    // Follow the pager without recomposing on every frame of a turn: only a
    // change of sheet rebuilds anything.
    LaunchedEffect(last) {
        snapshotFlow { page().toInt().coerceIn(0, last) }
            .distinctUntilChanged()
            .collect {
                leaf = it
                sheet = null
                backSheet = null
            }
    }

    // Take the sheets' pictures once the layers have recorded them. They
    // record in the draw phase, so let a frame go by first.
    LaunchedEffect(leaf, recorded, viewport, spread) {
        if (recorded.width <= 0 || recorded.height <= 0) return@LaunchedEffect
        withFrameNanos { }
        sheet = frontLayer.toImageBitmap()
        backSheet = if (spread) backLayer.toImageBitmap() else null
    }

    Box(
        Modifier.fillMaxSize().onSizeChanged { viewport = it },
        contentAlignment = Alignment.Center,
    ) {
        if (spread) {
            // Recorded and never drawn: the pager is already showing this
            // slide beneath the overlay. Its picture is wanted only for what
            // is printed on the back of the turning half. It is the whole
            // viewport, as the pager lays it out, so each part of it is where
            // it will lie once the turn is done.
            Box(
                Modifier.fillMaxSize().drawWithContent {
                    backLayer.record { this@drawWithContent.drawContent() }
                },
            ) {
                backSlide(leaf + 1)
            }
        }
        Box(
            Modifier.drawWithContent {
                frontLayer.record { this@drawWithContent.drawContent() }
                val measured = IntSize(size.width.roundToInt(), size.height.roundToInt())
                if (measured != recorded) recorded = measured
                val width = size.width
                if (width <= 0f) return@drawWithContent
                val progress = (page() - leaf).coerceIn(0f, 1f)
                if (progress <= 0f || progress >= 1f) return@drawWithContent
                // Where the sheet sits in the viewport it is centred in.
                val origin = Offset(
                    (viewport.width - width) / 2f,
                    (viewport.height - size.height) / 2f,
                )
                fadeMargins(viewport, origin, progress)
                val front = sheet?.asAndroidBitmap()
                if (front == null) {
                    // No picture yet: show the page flat, rather than letting
                    // the slide beneath flash through for a frame.
                    drawLayer(frontLayer)
                    return@drawWithContent
                }
                // Paper that has turned right over lands past the bound edge,
                // where there is no page any more: clipped off, as the book
                // clips it to the page rather than into the margin.
                clipRect(0f, 0f, width, size.height) {
                    if (spread) {
                        drawSpreadCurl(
                            front = front,
                            back = backSheet?.asAndroidBitmap(),
                            backOrigin = origin,
                            backArea = Size(viewport.width.toFloat(), viewport.height.toFloat()),
                            reverse = reverse,
                            progress = progress,
                        )
                    } else {
                        drawPageCurl(
                            front = front,
                            // Bound at the edge the reader turns away from,
                            // reaching across the page to the free edge it is
                            // lifted by.
                            spine = if (reverse) width else 0f,
                            direction = if (reverse) -1 else 1,
                            width = width,
                            progress = progress,
                            paper = paper,
                        )
                    }
                }
            },
        ) {
            slide(leaf)
        }
    }
}

/**
 * Fades the margins around the sheet from the slide being left to the one being
 * turned to.
 *
 * At rest everything outside a slide's pages is the reader's background.
 * Mid-turn the pager is already showing the next slide there, and when the two
 * slides are not the same size — scans rarely are, and a landscape page never
 * is — its edges would jump into the margins on the turn's first frame.
 * Covering them with the background, thinning as the turn goes, matches both
 * ends: the margins of the slide being left at 0, and of the slide being
 * turned to at 1. Drawn in the sheet's own coordinates, so the viewport starts
 * at minus [origin]; nothing inside the sheet is covered, since what the turn
 * has uncovered there is meant to show.
 */
private fun DrawScope.fadeMargins(viewport: IntSize, origin: Offset, progress: Float) {
    val alpha = (1f - progress).coerceIn(0f, 1f)
    if (alpha <= 0f || viewport.width <= 0 || viewport.height <= 0) return
    val left = -origin.x
    val top = -origin.y
    val right = left + viewport.width
    val bottom = top + viewport.height
    val color = ReaderBackdrop.copy(alpha = alpha)
    fun band(l: Float, t: Float, r: Float, b: Float) {
        if (r > l && b > t) drawRect(color, Offset(l, t), Size(r - l, b - t))
    }
    band(left, top, right, 0f)
    band(left, size.height, right, bottom)
    band(left, 0f, 0f, size.height)
    band(size.width, 0f, right, size.height)
}

/**
 * A spread turns about the spine down its middle, a half-page at a time.
 *
 * The sheet carries two pages, as a printed one does: the half being left on
 * its front, and the next slide on its [back], printed where it will lie, which
 * is how the new page arrives. [back] is a picture of the whole viewport, with
 * this sheet at [backOrigin] in it. The other half of the slide being left
 * stays down until the sheet lands on top of it, so it has to be painted over
 * the next slide, which the pager is already showing beneath the overlay. The
 * rest of the next slide needs nothing: it is meant to show. Once the sheet
 * lands, its back and what lies beyond it together are the next slide,
 * whatever its shape.
 */
private fun DrawScope.drawSpreadCurl(
    front: Bitmap,
    back: Bitmap?,
    backOrigin: Offset,
    backArea: Size,
    reverse: Boolean,
    progress: Float,
) {
    val spine = size.width / 2f
    // The half the reader is turning towards, whose page stays down.
    val stayingLeft = if (reverse) spine else 0f
    val stayingRight = if (reverse) size.width else spine
    val scaleX = front.width / size.width
    val canvas = drawContext.canvas.nativeCanvas
    canvas.drawRect(
        stayingLeft, 0f, stayingRight, size.height,
        Paint().apply { color = ReaderBackdrop.toArgb() },
    )
    canvas.drawBitmap(
        front,
        Rect(
            (stayingLeft * scaleX).roundToInt().coerceIn(0, front.width),
            0,
            (stayingRight * scaleX).roundToInt().coerceIn(0, front.width),
            front.height,
        ),
        RectF(stayingLeft, 0f, stayingRight, size.height),
        Paint().apply { isFilterBitmap = true },
    )
    drawPageCurl(
        front = front,
        back = back,
        backOrigin = backOrigin,
        backArea = backArea,
        spine = spine,
        direction = if (reverse) -1 else 1,
        width = spine,
        progress = progress,
        // Only ever seen in the letterbox around the pages, so the reader's
        // own background rather than a paper tone.
        paper = ReaderBackdrop,
    )
}

/**
 * Paints the sheet [PageCurl.layout] describes, in narrow vertical strips: each
 * a slice of [front] moved to where that slice of paper now sits, and shaded by
 * how far it faces away from the light. The page beneath takes a soft shadow
 * from the roll.
 *
 * [front] holds the whole page, at this scope's pixel size.
 */
fun DrawScope.drawPageCurl(
    front: Bitmap,
    spine: Float,
    direction: Int,
    width: Float,
    progress: Float,
    paper: Color,
    /** What is printed on the sheet's back; plain paper when null. */
    back: Bitmap? = null,
    /**
     * Where this sheet lies within [back], and the area [back] is a picture
     * of, when that is larger than the sheet.
     */
    backOrigin: Offset = Offset.Zero,
    backArea: Size? = null,
) {
    val height = size.height
    val curl = PageCurl.layout(spine, direction, width, progress) ?: return

    val canvas = drawContext.canvas.nativeCanvas
    val paperPaint = Paint().apply { color = paper.toArgb() }
    val imagePaint = Paint().apply { isFilterBitmap = true }
    // Show-through: the front, mirrored and faint, on the back of the sheet.
    val ghostPaint = Paint().apply { isFilterBitmap = true; alpha = 26 }
    val shadePaint = Paint()
    val src = Rect()
    val dst = RectF()

    // A sheet x maps onto a picture by its scale, from where the sheet lies in
    // it: the front is of the sheet itself, the back may be of more.
    fun band(
        bitmap: Bitmap,
        srcLeft: Float,
        srcRight: Float,
        dstLeft: Float,
        dstRight: Float,
        paint: Paint,
        origin: Offset = Offset.Zero,
        area: Size = size,
    ) {
        val sx = bitmap.width / area.width
        val sy = bitmap.height / area.height
        src.set(
            ((srcLeft + origin.x) * sx).roundToInt().coerceIn(0, bitmap.width),
            (origin.y * sy).roundToInt().coerceIn(0, bitmap.height),
            ((srcRight + origin.x) * sx).roundToInt().coerceIn(0, bitmap.width),
            ((origin.y + height) * sy).roundToInt().coerceIn(0, bitmap.height),
        )
        if (src.width() <= 0) return
        dst.set(dstLeft, 0f, dstRight, height)
        canvas.drawBitmap(bitmap, src, dst, paint)
    }

    // The part before the fold is still flat: one piece, so it has no seams.
    if (curl.flatRight > curl.flatLeft) {
        canvas.drawRect(curl.flatLeft, 0f, curl.flatRight, height, paperPaint)
        band(front, curl.flatLeft, curl.flatRight, curl.flatLeft, curl.flatRight, imagePaint)
    }

    // Each set is painted paper first, then print, then shade, so no strip's
    // paper covers its neighbour's edge, and no shade doubles up at a join.
    fun draw(strips: List<PageCurl.Strip>) {
        for (s in strips) canvas.drawRect(s.dstLeft, 0f, s.dstRight, height, paperPaint)
        for (s in strips) {
            if (!s.turned) {
                band(front, s.srcLeft, s.srcRight, s.dstLeft, s.dstRight, imagePaint)
            } else if (back != null) {
                // A page is printed on this side, where it will lie once the
                // sheet has turned right over.
                band(
                    back, s.backSrcLeft, s.backSrcRight, s.dstLeft, s.dstRight, imagePaint,
                    origin = backOrigin, area = backArea ?: size,
                )
            } else {
                val centre = (s.dstLeft + s.dstRight) / 2f
                canvas.save()
                canvas.translate(centre, 0f)
                canvas.scale(-1f, 1f)
                canvas.translate(-centre, 0f)
                band(front, s.srcLeft, s.srcRight, s.dstLeft, s.dstRight, ghostPaint)
                canvas.restore()
            }
        }
        for (s in strips) {
            if (s.shade <= 0.002f) continue
            shadePaint.color = Color.Black.copy(alpha = s.shade.coerceIn(0f, 0.6f)).toArgb()
            canvas.drawRect(s.dstLeft + 0.5f, 0f, s.dstRight - 0.5f, height, shadePaint)
        }
    }

    draw(curl.strips.filter { !it.turned })

    // The roll's shadow on the page beneath, just past its outer edge.
    if (curl.shadowStrength > 0.01f) {
        val edge = curl.shadowEdge
        val far = edge + direction * PageCurl.SHADOW_REACH
        drawRect(
            brush = Brush.horizontalGradient(
                0f to Color.Black.copy(alpha = curl.shadowStrength),
                1f to Color.Transparent,
                startX = edge,
                endX = far,
            ),
            topLeft = Offset(minOf(edge, far), 0f),
            size = Size(PageCurl.SHADOW_REACH, height),
        )
    }

    draw(curl.strips.filter { it.turned })
}
