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
 * chooses for itself, so the sheet is the page and not the window around it.
 */
@Composable
fun ComicPageCurl(
    page: () -> Float,
    reverse: Boolean,
    slideCount: Int,
    slide: @Composable (index: Int) -> Unit,
) {
    if (slideCount < 2) return
    val layer = rememberGraphicsLayer()
    val last = slideCount - 2
    // The slide being turned, kept composed and recorded even at rest, so its
    // picture is ready the moment a turn starts.
    var leaf by remember { mutableIntStateOf(page().toInt().coerceIn(0, last)) }
    var sheet by remember { mutableStateOf<ImageBitmap?>(null) }
    // The size the sheet was last recorded at, reported from the draw phase.
    var recorded by remember { mutableStateOf(IntSize.Zero) }

    // Follow the pager without recomposing on every frame of a turn: only a
    // change of sheet rebuilds anything.
    LaunchedEffect(last) {
        snapshotFlow { page().toInt().coerceIn(0, last) }
            .distinctUntilChanged()
            .collect {
                leaf = it
                sheet = null
            }
    }

    // Take the sheet's picture once the layer has recorded it. The layer records
    // in the draw phase, so let a frame go by first.
    LaunchedEffect(leaf, recorded) {
        if (recorded.width <= 0 || recorded.height <= 0) return@LaunchedEffect
        withFrameNanos { }
        sheet = layer.toImageBitmap()
    }

    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Box(
            Modifier.drawWithContent {
                layer.record { this@drawWithContent.drawContent() }
                val measured = IntSize(size.width.roundToInt(), size.height.roundToInt())
                if (measured != recorded) recorded = measured
                val width = size.width
                if (width <= 0f) return@drawWithContent
                val progress = (page() - leaf).coerceIn(0f, 1f)
                if (progress <= 0f || progress >= 1f) return@drawWithContent
                val bitmap = sheet?.asAndroidBitmap()
                if (bitmap == null) {
                    // No picture yet: show the page flat, rather than letting
                    // the slide beneath flash through for a frame.
                    drawLayer(layer)
                    return@drawWithContent
                }
                // Paper that has turned right over lands past the bound edge,
                // where there is no page any more: clipped off, as the book
                // clips it to the page rather than into the margin.
                clipRect(0f, 0f, width, size.height) {
                    drawPageCurl(
                        front = bitmap,
                        // Bound at the edge the reader turns away from, reaching
                        // across the page to the free edge it is lifted by.
                        spine = if (reverse) width else 0f,
                        direction = if (reverse) -1 else 1,
                        progress = progress,
                        paper = ReaderPaper,
                    )
                }
            },
        ) {
            slide(leaf)
        }
    }
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
    progress: Float,
    paper: Color,
) {
    val width = size.width
    val height = size.height
    val curl = PageCurl.layout(spine, direction, width, progress) ?: return

    val canvas = drawContext.canvas.nativeCanvas
    // The picture is of the whole sheet, so a sheet x maps straight onto it.
    val scaleX = front.width / width
    val paperPaint = Paint().apply { color = paper.toArgb() }
    val imagePaint = Paint().apply { isFilterBitmap = true }
    // Show-through: the front, mirrored and faint, on the back of the sheet.
    val ghostPaint = Paint().apply { isFilterBitmap = true; alpha = 26 }
    val shadePaint = Paint()
    val src = Rect()
    val dst = RectF()

    fun band(srcLeft: Float, srcRight: Float, dstLeft: Float, dstRight: Float, paint: Paint) {
        src.set(
            (srcLeft * scaleX).roundToInt().coerceIn(0, front.width),
            0,
            (srcRight * scaleX).roundToInt().coerceIn(0, front.width),
            front.height,
        )
        if (src.width() <= 0) return
        dst.set(dstLeft, 0f, dstRight, height)
        canvas.drawBitmap(front, src, dst, paint)
    }

    // The part before the fold is still flat: one piece, so it has no seams.
    if (curl.flatRight > curl.flatLeft) {
        canvas.drawRect(curl.flatLeft, 0f, curl.flatRight, height, paperPaint)
        band(curl.flatLeft, curl.flatRight, curl.flatLeft, curl.flatRight, imagePaint)
    }

    // Each set is painted paper first, then print, then shade, so no strip's
    // paper covers its neighbour's edge, and no shade doubles up at a join.
    fun draw(strips: List<PageCurl.Strip>) {
        for (s in strips) canvas.drawRect(s.dstLeft, 0f, s.dstRight, height, paperPaint)
        for (s in strips) {
            if (!s.turned) {
                band(s.srcLeft, s.srcRight, s.dstLeft, s.dstRight, imagePaint)
            } else {
                val centre = (s.dstLeft + s.dstRight) / 2f
                canvas.save()
                canvas.translate(centre, 0f)
                canvas.scale(-1f, 1f)
                canvas.translate(-centre, 0f)
                band(s.srcLeft, s.srcRight, s.dstLeft, s.dstRight, ghostPaint)
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
