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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
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

    val slides = if (state.doublePage)
        buildSlides(state.totalPages, state.spreads)
    else
        List(state.totalPages) { listOf(it) }

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
                    modifier = Modifier.align(Alignment.Center),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    androidx.compose.material3.CircularProgressIndicator(color = Color.White)
                    androidx.compose.material3.Text(
                        "Preparing archive…",
                        color = Color.White.copy(alpha = 0.7f),
                    )
                }
            } else if (state.scrollMode) {
                ScrollModeContent(
                    state = state,
                    imageModelFn = ::imageModel,
                    onTap = ::toggleHud,
                    onPrevChapter = ::tryPrevChapter,
                    onNextChapter = ::tryNextChapter,
                    onPageChange = { vm.onPageChange(it) },
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
) {
    val listState = rememberLazyListState()

    // Jump to saved page once totalPages is known
    LaunchedEffect(state.totalPages, state.initialPage) {
        if (state.totalPages > 0 && state.initialPage > 0) {
            listState.scrollToItem(state.initialPage)
        }
    }

    // Track current page from first visible item
    LaunchedEffect(listState.firstVisibleItemIndex) {
        onPageChange(listState.firstVisibleItemIndex)
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
    var isZoomed by remember { mutableStateOf(false) }

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

    // Jump to initial/saved page once pages load
    LaunchedEffect(state.totalPages, state.initialPage) {
        if (state.totalPages > 0) {
            val slideIndex = slides.indexWhere { it.contains(state.initialPage) }
                .coerceAtLeast(0)
            pagerState.scrollToPage(slideIndex)
        }
    }

    // Sync pager → ViewModel current page
    LaunchedEffect(pagerState.currentPage) {
        if (state.totalPages > 0) {
            val pageIndex = slides.getOrNull(pagerState.currentPage)?.first() ?: pagerState.currentPage
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
                detectTapGestures { offset ->
                    val width = size.width.toFloat()
                    when {
                        // Left third: prev in LTR, next in RTL
                        offset.x < width / 3f -> if (state.isRtl) goForward() else goBack()
                        // Right third: next in LTR, prev in RTL
                        offset.x > width * 2f / 3f -> if (state.isRtl) goBack() else goForward()
                        // Centre: toggle HUD
                        else -> onTap()
                    }
                }
            },
        beyondViewportPageCount = 4,
    ) { viewIndex ->
        val slide = slides.getOrNull(viewIndex) ?: return@HorizontalPager

        if (slide.size == 1) {
            ZoomablePageImage(
                model = imageModelFn(slide[0]),
                modifier = Modifier.fillMaxSize(),
                onZoomChanged = { isZoomed = it },
            )
        } else {
            val left = if (state.isRtl) slide[1] else slide[0]
            val right = if (state.isRtl) slide[0] else slide[1]
            Row(Modifier.fillMaxSize()) {
                ZoomablePageImage(
                    model = imageModelFn(left),
                    modifier = Modifier.weight(1f).fillMaxHeight(),
                    onZoomChanged = { isZoomed = it },
                )
                if (state.spineGap > 0f) {
                    Box(Modifier.fillMaxHeight().padding(horizontal = (state.spineGap / 2).dp))
                }
                ZoomablePageImage(
                    model = imageModelFn(right),
                    modifier = Modifier.weight(1f).fillMaxHeight(),
                    onZoomChanged = { isZoomed = it },
                )
            }
        }
    }

}

// ── Zoomable image ────────────────────────────────────────────────────────────

@Composable
private fun ZoomablePageImage(
    model: Any,
    modifier: Modifier = Modifier,
    onZoomChanged: (Boolean) -> Unit = {},
) {
    var scale by remember { mutableFloatStateOf(1f) }
    var offsetX by remember { mutableFloatStateOf(0f) }
    var offsetY by remember { mutableFloatStateOf(0f) }

    LaunchedEffect(model) {
        scale = 1f; offsetX = 0f; offsetY = 0f
        onZoomChanged(false)
    }

    SubcomposeAsyncImage(
        model = model,
        contentDescription = null,
        contentScale = ContentScale.Fit,
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
                                    onZoomChanged(newScale > 1f)
                                    if (newScale <= 1f) { offsetX = 0f; offsetY = 0f }
                                }
                                pressed.forEach { it.consume() }
                                pointerCount = pressed.size
                            }
                            pressed.size == 1 && scale > 1f -> {
                                // Single-touch pan while zoomed
                                val delta = pressed[0].positionChange()
                                offsetX += delta.x
                                offsetY += delta.y
                                pressed[0].consume()
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
            .graphicsLayer(scaleX = scale, scaleY = scale, translationX = offsetX, translationY = offsetY),
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
