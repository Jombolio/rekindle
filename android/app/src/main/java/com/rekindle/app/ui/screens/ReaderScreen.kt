package com.rekindle.app.ui.screens

import android.net.Uri
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AutoStories
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.automirrored.filled.FormatTextdirectionLToR
import androidx.compose.material.icons.automirrored.filled.FormatTextdirectionRToL
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.ViewCarousel
import androidx.compose.material.icons.filled.ViewDay
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import coil.compose.AsyncImage
import coil.compose.AsyncImagePainter
import coil.compose.SubcomposeAsyncImage
import coil.compose.SubcomposeAsyncImageContent
import coil.request.ImageRequest
import com.rekindle.app.ui.viewmodel.ReaderViewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch
import java.io.File

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReaderScreen(
    mediaId: String,
    onBack: () -> Unit,
    onNavigateToChapter: (targetId: String, initialPage: Int) -> Unit,
    vm: ReaderViewModel = hiltViewModel(),
) {
    val state by vm.state.collectAsState()
    val context = LocalContext.current

    // ── HUD auto-hide ─────────────────────────────────────────────────────────
    var hudVisible by remember { mutableStateOf(true) }
    var interactionTick by remember { mutableIntStateOf(0) }
    LaunchedEffect(interactionTick) {
        hudVisible = true
        delay(3_000)
        hudVisible = false
    }
    fun showHud() { interactionTick++ }
    fun toggleHud() { if (hudVisible) { hudVisible = false } else { interactionTick++ } }

    // ── Chapter navigation event ──────────────────────────────────────────────
    LaunchedEffect(state.navigateToChapterId) {
        val targetId = state.navigateToChapterId ?: return@LaunchedEffect
        val ip = state.navigateToChapterInitialPage
        vm.clearNavigation()
        onNavigateToChapter(targetId, ip)
    }

    // ── Slide layout (double-page groups) ────────────────────────────────────
    fun buildSlides(totalPages: Int, spreads: List<Boolean>): List<List<Int>> {
        val slides = mutableListOf<List<Int>>()
        var i = 0
        while (i < totalPages) {
            val isSpread = i < spreads.size && spreads[i]
            if (isSpread || i == 0) {
                slides.add(listOf(i)); i++
            } else {
                val nextSpread = (i + 1) < spreads.size && spreads[i + 1]
                if (i + 1 < totalPages && !nextSpread) {
                    slides.add(listOf(i, i + 1)); i += 2
                } else {
                    slides.add(listOf(i)); i++
                }
            }
        }
        return slides
    }

    val slides = remember(state.totalPages, state.spreads, state.doublePage) {
        if (state.doublePage)
            buildSlides(state.totalPages, state.spreads)
        else
            List(state.totalPages) { listOf(it) }
    }

    val slideCount = slides.size.coerceAtLeast(1)

    // ── Chapter helpers ───────────────────────────────────────────────────────
    fun tryPrevChapter() {
        val idx = state.siblings.indexWhere { it.id == mediaId }
        if (idx > 0) vm.navigateToChapter(state.siblings[idx - 1].id, 0)
    }

    fun tryNextChapter() {
        val idx = state.siblings.indexWhere { it.id == mediaId }
        if (idx >= 0 && idx < state.siblings.size - 1)
            vm.navigateToChapter(state.siblings[idx + 1].id, 0)
    }

    // ── Image model helper ────────────────────────────────────────────────────
    fun imageModel(pageIndex: Int): Any {
        val extracted = state.extractedPages
        return if (extracted != null && pageIndex < extracted.size) {
            Uri.fromFile(File(extracted[pageIndex]))
        } else {
            ImageRequest.Builder(context)
                .data(vm.pageUrl(pageIndex))
                .addHeader("Authorization", vm.authHeader)
                .build()
        }
    }

    Scaffold(
        containerColor = Color.Black,
        topBar = {},
        bottomBar = {},
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .background(Color.Black)
        ) {
            if (state.totalPages == 0) {
                Column(
                    modifier = Modifier.align(Alignment.Center).padding(32.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    if (state.pagesUnavailable) {
                        androidx.compose.material3.Text(
                            "This item isn't available offline yet. Connect to your server to download or stream it.",
                            color = Color.White,
                        )
                        androidx.compose.material3.TextButton(onClick = onBack) {
                            androidx.compose.material3.Text("Back")
                        }
                    } else {
                        androidx.compose.material3.CircularProgressIndicator(color = Color.White)
                        androidx.compose.material3.Text(
                            "Preparing archive…",
                            color = Color.White.copy(alpha = 0.7f),
                        )
                    }
                }
            } else if (state.scrollMode) {
                ScrollModeContent(
                    state = state,
                    imageModelFn = ::imageModel,
                    onTap = ::toggleHud,
                    onPrevChapter = ::tryPrevChapter,
                    onNextChapter = ::tryNextChapter,
                    onPageChange = { vm.onPageChange(it) },
                    onSeekClear = { vm.clearSeek() },
                )
            } else {
                PagedModeContent(
                    state = state,
                    slides = slides,
                    slideCount = slideCount,
                    imageModelFn = ::imageModel,
                    onTap = ::toggleHud,
                    onPrevChapter = ::tryPrevChapter,
                    onNextChapter = ::tryNextChapter,
                    onPageChange = { vm.onPageChange(it) },
                    onSeekClear = { vm.clearSeek() },
                )
            }

            // ── HUD overlay ───────────────────────────────────────────────────
            AnimatedVisibility(
                visible = hudVisible,
                enter = fadeIn(),
                exit = fadeOut(),
            ) {
                Box(Modifier.fillMaxSize()) {
                    // Top bar
                    TopAppBar(
                        title = { Text(state.title, color = Color.White) },
                        navigationIcon = {
                            IconButton(onClick = onBack) {
                                Icon(Icons.AutoMirrored.Filled.ArrowBack, null, tint = Color.White)
                            }
                        },
                        actions = {
                            // Scroll mode toggle
                            IconButton(onClick = { vm.toggleScrollMode(); showHud() }) {
                                Icon(
                                    if (state.scrollMode) Icons.Default.ViewCarousel else Icons.Default.ViewDay,
                                    contentDescription = if (state.scrollMode) "Paged mode" else "Scroll mode",
                                    tint = Color.White,
                                )
                            }
                            // Double-page toggle (paged mode only)
                            if (!state.scrollMode) {
                                IconButton(onClick = { vm.toggleDoublePage(); showHud() }) {
                                    Icon(
                                        if (state.doublePage) Icons.AutoMirrored.Filled.MenuBook else Icons.Default.AutoStories,
                                        contentDescription = if (state.doublePage) "Single page" else "Double page",
                                        tint = Color.White,
                                    )
                                }
                            }
                            // Spine gap –/+ (double-page paged mode)
                            if (!state.scrollMode && state.doublePage) {
                                IconButton(
                                    onClick = { vm.updateSpineGap(state.spineGap - 4f); showHud() },
                                    enabled = state.spineGap > 0f,
                                ) {
                                    Icon(Icons.Default.Remove, null, tint = Color.White, modifier = Modifier.size(16.dp))
                                }
                                Text(
                                    "${state.spineGap.toInt()}",
                                    color = Color.White.copy(alpha = 0.7f),
                                )
                                IconButton(
                                    onClick = { vm.updateSpineGap(state.spineGap + 4f); showHud() },
                                    enabled = state.spineGap < 64f,
                                ) {
                                    Icon(Icons.Default.Add, null, tint = Color.White, modifier = Modifier.size(16.dp))
                                }
                            }
                            // RTL toggle (paged mode only)
                            if (!state.scrollMode) {
                                IconButton(onClick = { vm.toggleDirection(); showHud() }) {
                                    Icon(
                                        if (state.isRtl) Icons.AutoMirrored.Filled.FormatTextdirectionRToL
                                        else Icons.AutoMirrored.Filled.FormatTextdirectionLToR,
                                        contentDescription = if (state.isRtl) "RTL" else "LTR",
                                        tint = Color.White,
                                    )
                                }
                            }
                        },
                        colors = TopAppBarDefaults.topAppBarColors(
                            containerColor = Color.Black.copy(alpha = 0.7f),
                        ),
                        modifier = Modifier.align(Alignment.TopCenter),
                    )

                    // Bottom slider
                    if (state.totalPages > 1) {
                        var sliderValue by remember(state.currentPage) {
                            mutableFloatStateOf(state.currentPage.toFloat())
                        }
                        CompositionLocalProvider(
                            LocalLayoutDirection provides if (state.isRtl && !state.scrollMode)
                                LayoutDirection.Rtl else LayoutDirection.Ltr
                        ) {
                            Box(
                                modifier = Modifier
                                    .align(Alignment.BottomCenter)
                                    .fillMaxWidth()
                                    .background(Color.Black.copy(alpha = 0.7f))
                                    .padding(horizontal = 16.dp, vertical = 8.dp),
                            ) {
                                Slider(
                                    value = sliderValue,
                                    onValueChange = { sliderValue = it },
                                    onValueChangeFinished = {
                                        val page = sliderValue.toInt()
                                        vm.onPageChange(page)
                                        vm.seekToPage(page)
                                    },
                                    valueRange = 0f..(state.totalPages - 1).toFloat(),
                                    steps = (state.totalPages - 2).coerceAtLeast(0),
                                )
                                Text(
                                    "${state.currentPage + 1} / ${state.totalPages}",
                                    color = Color.White,
                                    modifier = Modifier.align(Alignment.TopEnd),
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

// ── Scroll mode ───────────────────────────────────────────────────────────────

@Composable
private fun ScrollModeContent(
    state: com.rekindle.app.ui.viewmodel.ReaderState,
    imageModelFn: (Int) -> Any,
    onTap: () -> Unit,
    onPrevChapter: () -> Unit,
    onNextChapter: () -> Unit,
    onPageChange: (Int) -> Unit,
    onSeekClear: () -> Unit,
) {
    val listState = rememberLazyListState()

    // Restore the LIVE reading position on (re)mount — state.currentPage, not
    // the never-updated initialPage, so toggling scroll/paged mode keeps the
    // user's place instead of teleporting back to the originally-resumed page.
    // Content only composes once totalPages > 0, so no gating is needed.
    LaunchedEffect(Unit) {
        if (state.currentPage > 0) {
            listState.scrollToItem(state.currentPage)
        }
    }

    // Consume slider seeks — without this the slider did nothing in scroll mode
    // and the un-cleared seek fired later when switching to paged mode.
    LaunchedEffect(state.seekToPage) {
        if (state.seekToPage >= 0) {
            listState.scrollToItem(state.seekToPage)
            onSeekClear()
        }
    }

    // Track the current page. firstVisibleItemIndex alone can never equal the
    // final page index when that page is shorter than the viewport, so books
    // finished in scroll mode were stored as in-progress forever (and resumed
    // at the end instead of restarting). Report the last page once its bottom
    // edge is fully on screen.
    LaunchedEffect(listState) {
        snapshotFlow {
            val info = listState.layoutInfo
            val last = info.visibleItemsInfo.lastOrNull()
            if (last != null && last.index == info.totalItemsCount - 1 &&
                last.offset + last.size <= info.viewportEndOffset
            ) {
                last.index
            } else {
                listState.firstVisibleItemIndex
            }
        }
            .distinctUntilChanged()
            .collect { onPageChange(it) }
    }

    LazyColumn(
        state = listState,
        modifier = Modifier
            .fillMaxSize()
            .pointerInput(Unit) { detectTapGestures(onTap = { onTap() }) },
    ) {
        items(state.totalPages) { pageIndex ->
            SubcomposeAsyncImage(
                model = imageModelFn(pageIndex),
                contentDescription = null,
                contentScale = ContentScale.FillWidth,
                modifier = Modifier
                    .fillMaxWidth()
                    .background(Color.Black),
            ) {
                when (painter.state) {
                    is AsyncImagePainter.State.Loading, is AsyncImagePainter.State.Empty ->
                        Box(
                            Modifier.fillMaxWidth().aspectRatio(0.67f),
                            contentAlignment = Alignment.Center,
                        ) {
                            androidx.compose.material3.CircularProgressIndicator(
                                color = Color.White,
                                modifier = Modifier.size(32.dp),
                                strokeWidth = 2.dp,
                            )
                        }
                    is AsyncImagePainter.State.Error ->
                        Box(
                            Modifier.fillMaxWidth().aspectRatio(0.67f),
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(Icons.Default.ErrorOutline, contentDescription = null, tint = Color.White.copy(0.4f), modifier = Modifier.size(48.dp))
                        }
                    else -> SubcomposeAsyncImageContent()
                }
            }
        }
    }
}

// ── Paged mode ────────────────────────────────────────────────────────────────

@Composable
private fun PagedModeContent(
    state: com.rekindle.app.ui.viewmodel.ReaderState,
    slides: List<List<Int>>,
    slideCount: Int,
    imageModelFn: (Int) -> Any,
    onTap: () -> Unit,
    onPrevChapter: () -> Unit,
    onNextChapter: () -> Unit,
    onPageChange: (Int) -> Unit,
    onSeekClear: () -> Unit,
) {
    val pagerState = rememberPagerState(pageCount = { slideCount })
    val scope = rememberCoroutineScope()
    // Single hoisted zoom state for the *current* slide. Sharing one instance lets
    // the pager-level double-tap reset it, and keeps the pinch/pan transform reads
    // in the draw phase (see ZoomablePageImage) instead of triggering recomposition.
    val zoom = remember { ZoomState() }
    val isZoomed by remember { derivedStateOf { zoom.scale.floatValue > 1f } }

    // Advance one slide forward, or navigate to next chapter at the last slide.
    fun goForward() = scope.launch {
        if (pagerState.currentPage < slideCount - 1)
            pagerState.animateScrollToPage(pagerState.currentPage + 1)
        else
            onNextChapter()
    }

    // Advance one slide backward, or navigate to prev chapter at the first slide.
    fun goBack() = scope.launch {
        if (pagerState.currentPage > 0)
            pagerState.animateScrollToPage(pagerState.currentPage - 1)
        else
            onPrevChapter()
    }

    // Restore/remap. Fires at mount (jump to the slide containing the live
    // currentPage — not the never-updated initialPage, so a scroll/paged mode
    // toggle keeps the user's place) and again whenever the slide grouping
    // changes (the server spread map arriving after a local-manifest open, or a
    // corrected page count). Re-mapping through the OLD grouping keeps the same
    // logical page on screen instead of letting the pager's retained numeric
    // index silently point at different pages.
    var prevSlides by remember { mutableStateOf<List<List<Int>>?>(null) }
    // Slide index of an in-flight programmatic jump; -1 when idle. The sync
    // effect below must not report programmatic jumps as reading progress.
    var programmaticTarget by remember { mutableIntStateOf(-1) }
    LaunchedEffect(slides) {
        val anchor = prevSlides?.getOrNull(pagerState.currentPage)?.lastOrNull()
            ?: state.currentPage
        prevSlides = slides
        val target = slides.indexWhere { it.contains(anchor) }.coerceAtLeast(0)
        if (target != pagerState.currentPage) {
            programmaticTarget = target
            pagerState.scrollToPage(target)
        }
    }

    // Sync pager → ViewModel current page. Also drop any zoom from the page we left
    // so every slide starts at the fit-to-screen view.
    LaunchedEffect(pagerState.currentPage) {
        zoom.reset()
        if (state.totalPages > 0) {
            // Skip while a restore/remap jump is in flight: the ViewModel already
            // holds the logical page, and reporting the new slide's last page here
            // is what crept progress forward whenever slide grouping differed
            // between sessions (e.g. offline opens have no spreads array).
            if (programmaticTarget != -1) {
                if (pagerState.currentPage == programmaticTarget) programmaticTarget = -1
                return@LaunchedEffect
            }
            // Report the LAST page of the slide so finishing a book on a double-
            // page spread reaches totalPages-1 and marks completion.
            val pageIndex = slides.getOrNull(pagerState.currentPage)?.last() ?: pagerState.currentPage
            onPageChange(pageIndex)
        }
    }

    // Seek from slider
    val seekPage = state.seekToPage
    LaunchedEffect(seekPage) {
        if (seekPage >= 0) {
            val slide = slides.indexWhere { it.contains(seekPage) }.coerceAtLeast(0)
            pagerState.scrollToPage(slide)
            onSeekClear()
        }
    }

    HorizontalPager(
        state = pagerState,
        reverseLayout = state.isRtl,
        userScrollEnabled = !isZoomed,
        modifier = Modifier
            .fillMaxSize()
            .pointerInput(state.isRtl) {
                detectTapGestures(
                    // Double-tap toggles between the fit view and a fixed zoom, and is
                    // the reliable way back to the original view once zoomed in.
                    onDoubleTap = {
                        if (zoom.scale.floatValue > 1f) {
                            zoom.reset()
                        } else {
                            zoom.scale.floatValue = 2.5f
                        }
                    },
                    onTap = { offset ->
                        val width = size.width.toFloat()
                        when {
                            // While zoomed, a tap only toggles the HUD — never flips
                            // pages, so panning isn't interrupted by a stray page turn.
                            zoom.scale.floatValue > 1f -> onTap()
                            // Left third: prev in LTR, next in RTL
                            offset.x < width / 3f -> if (state.isRtl) goForward() else goBack()
                            // Right third: next in LTR, prev in RTL
                            offset.x > width * 2f / 3f -> if (state.isRtl) goBack() else goForward()
                            // Centre: toggle HUD
                            else -> onTap()
                        }
                    },
                )
            },
        beyondViewportPageCount = 4,
    ) { viewIndex ->
        val slide = slides.getOrNull(viewIndex) ?: return@HorizontalPager
        // Only the settled slide owns the shared zoom; neighbours (kept alive by
        // beyondViewportPageCount) render at the fit view so a leftover zoom never
        // bleeds onto the next page mid-swipe.
        val isCurrent = viewIndex == pagerState.currentPage

        if (slide.size == 1) {
            ZoomablePageImage(
                model = imageModelFn(slide[0]),
                modifier = Modifier.fillMaxSize(),
                zoom = zoom,
                applyTransform = isCurrent,
            )
        } else {
            val left = if (state.isRtl) slide[1] else slide[0]
            val right = if (state.isRtl) slide[0] else slide[1]
            // graphicsLayer is on the Row (spread centre = W/2) so both pages zoom
            // around the same origin instead of each zooming around their own centre.
            Row(
                Modifier.fillMaxSize().graphicsLayer {
                    val s = if (isCurrent) zoom.scale.floatValue else 1f
                    scaleX = s; scaleY = s
                    translationX = if (isCurrent) zoom.offsetX.floatValue else 0f
                    translationY = if (isCurrent) zoom.offsetY.floatValue else 0f
                }
            ) {
                ZoomablePageImage(
                    model = imageModelFn(left),
                    modifier = Modifier.weight(1f).fillMaxHeight(),
                    alignment = androidx.compose.ui.Alignment.CenterEnd,
                    zoom = zoom,
                    applyTransform = false,
                )
                if (state.spineGap > 0f) {
                    Box(Modifier.fillMaxHeight().padding(horizontal = (state.spineGap / 2).dp))
                }
                ZoomablePageImage(
                    model = imageModelFn(right),
                    modifier = Modifier.weight(1f).fillMaxHeight(),
                    alignment = androidx.compose.ui.Alignment.CenterStart,
                    zoom = zoom,
                    applyTransform = false,
                )
            }
        }
    }

}

// ── Shared zoom state ─────────────────────────────────────────────────────────
// One instance is hoisted per pager and reused for whichever slide is current;
// double-page spreads read it from the Row so both halves stay synchronised.

private class ZoomState {
    val scale   = mutableFloatStateOf(1f)
    val offsetX = mutableFloatStateOf(0f)
    val offsetY = mutableFloatStateOf(0f)

    fun reset() {
        scale.floatValue = 1f
        offsetX.floatValue = 0f
        offsetY.floatValue = 0f
    }
}

// ── Zoomable image ────────────────────────────────────────────────────────────

@Composable
private fun ZoomablePageImage(
    model: Any,
    modifier: Modifier = Modifier,
    alignment: androidx.compose.ui.Alignment = androidx.compose.ui.Alignment.Center,
    zoom: ZoomState = remember { ZoomState() },
    // Set false for double-page spreads: the parent Row owns the graphicsLayer
    // so both pages zoom/pan around the spread centre, not each page's own centre.
    // Also gates offset clamping, which only makes sense against a full-viewport page.
    applyTransform: Boolean = true,
) {
    // Delegate to the shared state so double-page spreads stay synchronised while
    // single pages continue to work unchanged.
    var scale   by zoom.scale
    var offsetX by zoom.offsetX
    var offsetY by zoom.offsetY

    SubcomposeAsyncImage(
        model = model,
        contentDescription = null,
        contentScale = ContentScale.Fit,
        alignment = alignment,
        modifier = modifier
            .background(Color.Black)
            // Custom gesture handler: only consumes multi-touch (pinch zoom) and
            // single-touch pan WHEN already zoomed. Single-touch at scale 1 is NOT
            // consumed so the parent HorizontalPager can detect page-swipe gestures.
            .pointerInput(Unit) {
                awaitEachGesture {
                    awaitFirstDown(requireUnconsumed = false)

                    var pointerCount = 1
                    var initialSpan = 0f
                    var scaleAtPinchStart = scale

                    while (true) {
                        val event = awaitPointerEvent()
                        val pressed = event.changes.filter { it.pressed }
                        if (pressed.isEmpty()) break

                        when {
                            pressed.size >= 2 -> {
                                // Multi-touch pinch → zoom
                                val span = (pressed[0].position - pressed[1].position).getDistance()
                                if (pointerCount < 2) {
                                    initialSpan = span
                                    scaleAtPinchStart = scale
                                } else if (initialSpan > 0f) {
                                    val newScale = (scaleAtPinchStart * span / initialSpan)
                                        .coerceIn(1f, 5f)
                                    scale = newScale
                                    if (newScale <= 1f) {
                                        offsetX = 0f; offsetY = 0f
                                    } else if (applyTransform) {
                                        // Keep the panned image within its own bounds as it shrinks.
                                        val mx = size.width * (newScale - 1f) / 2f
                                        val my = size.height * (newScale - 1f) / 2f
                                        offsetX = offsetX.coerceIn(-mx, mx)
                                        offsetY = offsetY.coerceIn(-my, my)
                                    }
                                }
                                pressed.forEach { it.consume() }
                                pointerCount = pressed.size
                            }
                            pressed.size == 1 && scale > 1f -> {
                                // Single-touch pan while zoomed. Clamp to the image
                                // bounds so it can't drift off into empty space.
                                val delta = pressed[0].positionChange()
                                if (applyTransform) {
                                    val mx = size.width * (scale - 1f) / 2f
                                    val my = size.height * (scale - 1f) / 2f
                                    offsetX = (offsetX + delta.x).coerceIn(-mx, mx)
                                    offsetY = (offsetY + delta.y).coerceIn(-my, my)
                                } else {
                                    offsetX += delta.x
                                    offsetY += delta.y
                                }
                                // Only consume once the finger actually moves. A stationary
                                // tap stays unconsumed so the pager's tap/double-tap detector
                                // still fires — that's how double-tap resets the zoom.
                                if (delta.x != 0f || delta.y != 0f) pressed[0].consume()
                                pointerCount = 1
                            }
                            else -> {
                                // Single-touch at scale 1 — pass through to the pager
                                pointerCount = pressed.size
                            }
                        }
                    }
                }
            }
            // Lambda form: scale/offset are read in the draw phase, so pinch and pan
            // update the layer without recomposing this (expensive) SubcomposeAsyncImage
            // every frame. The eager graphicsLayer(scaleX = …) form recomposed on every
            // gesture event, which made panning lag worse the longer it continued.
            .graphicsLayer {
                if (applyTransform) {
                    scaleX = scale; scaleY = scale
                    translationX = offsetX; translationY = offsetY
                }
            },
    ) {
        when (painter.state) {
            is AsyncImagePainter.State.Loading, is AsyncImagePainter.State.Empty ->
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    androidx.compose.material3.CircularProgressIndicator(
                        color = Color.White,
                        modifier = Modifier.size(48.dp),
                        strokeWidth = 3.dp,
                    )
                }
            is AsyncImagePainter.State.Error ->
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Icon(Icons.Default.ErrorOutline, contentDescription = null, tint = Color.White.copy(0.4f), modifier = Modifier.size(64.dp))
                }
            else -> SubcomposeAsyncImageContent()
        }
    }
}

// ── Extension ─────────────────────────────────────────────────────────────────

private fun <T> List<T>.indexWhere(predicate: (T) -> Boolean): Int =
    indexOfFirst(predicate)
