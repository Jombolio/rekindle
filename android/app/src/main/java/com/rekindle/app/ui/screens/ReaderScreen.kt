package com.rekindle.app.ui.screens

import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.AutoStories
import androidx.compose.material.icons.filled.FormatTextdirectionLToR
import androidx.compose.material.icons.filled.FormatTextdirectionRToL
import androidx.compose.material.icons.filled.MenuBook
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import coil.compose.AsyncImage
import coil.request.ImageRequest
import com.rekindle.app.ui.viewmodel.ReaderViewModel
import java.io.File

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReaderScreen(
    mediaId: String,
    onBack: () -> Unit,
    vm: ReaderViewModel = hiltViewModel(),
) {
    val state by vm.state.collectAsState()
    val context = LocalContext.current

    val slideCount = if (state.doublePage) (state.totalPages + 1) / 2 else state.totalPages
    val pagerState = rememberPagerState(pageCount = { slideCount.coerceAtLeast(1) })

    LaunchedEffect(state.totalPages, state.initialPage) {
        if (state.totalPages > 0 && state.initialPage > 0) {
            val slideIndex = if (state.doublePage) state.initialPage / 2 else state.initialPage
            pagerState.scrollToPage(slideIndex)
        }
    }

    LaunchedEffect(pagerState.currentPage) {
        if (state.totalPages > 0) {
            val pageIndex = if (state.doublePage) pagerState.currentPage * 2 else pagerState.currentPage
            vm.onPageChange(pageIndex)
        }
    }

    if (state.totalPages == 0) {
        Box(Modifier.fillMaxSize().background(Color.Black), contentAlignment = Alignment.Center) {
            CircularProgressIndicator(color = Color.White)
        }
        return
    }

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
        topBar = {
            if (state.showControls) {
                TopAppBar(
                    title = { Text(state.title, color = Color.White) },
                    navigationIcon = {
                        IconButton(onClick = onBack) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, null, tint = Color.White)
                        }
                    },
                    actions = {
                        IconButton(onClick = { vm.toggleDoublePage() }) {
                            Icon(
                                imageVector = if (state.doublePage) Icons.Default.MenuBook else Icons.Default.AutoStories,
                                contentDescription = if (state.doublePage) "Single page" else "Double page",
                                tint = Color.White,
                            )
                        }
                        IconButton(onClick = { vm.toggleDirection() }) {
                            Icon(
                                imageVector = if (state.isRtl) Icons.Default.FormatTextdirectionRToL else Icons.Default.FormatTextdirectionLToR,
                                contentDescription = if (state.isRtl) "RTL" else "LTR",
                                tint = Color.White,
                            )
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Black.copy(alpha = 0.7f)),
                )
            }
        },
        bottomBar = {
            if (state.showControls && state.totalPages > 1) {
                var sliderValue by remember(state.currentPage) {
                    mutableFloatStateOf(state.currentPage.toFloat())
                }
                Box(
                    modifier = Modifier
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
        },
    ) { padding ->
        var isZoomed by remember { mutableStateOf(false) }

        HorizontalPager(
            state = pagerState,
            reverseLayout = state.isRtl,
            userScrollEnabled = !isZoomed,
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .pointerInput(Unit) {
                    detectTapGestures(onTap = { vm.toggleControls() })
                },
        ) { viewIndex ->
            if (state.doublePage) {
                val left = viewIndex * 2
                val right = left + 1
                Row(Modifier.fillMaxSize()) {
                    ZoomablePageImage(
                        model = imageModel(if (state.isRtl && right < state.totalPages) right else left),
                        modifier = Modifier.weight(1f).fillMaxHeight(),
                        onZoomChanged = { isZoomed = it },
                    )
                    if ((if (state.isRtl) left else right) < state.totalPages) {
                        ZoomablePageImage(
                            model = imageModel(if (state.isRtl) left else right),
                            modifier = Modifier.weight(1f).fillMaxHeight(),
                            onZoomChanged = { isZoomed = it },
                        )
                    }
                }
            } else {
                ZoomablePageImage(
                    model = imageModel(viewIndex),
                    modifier = Modifier.fillMaxSize(),
                    onZoomChanged = { isZoomed = it },
                )
            }
        }

        val seekPage = state.seekToPage
        LaunchedEffect(seekPage) {
            if (seekPage >= 0) {
                val slide = if (state.doublePage) seekPage / 2 else seekPage
                pagerState.scrollToPage(slide)
                vm.clearSeek()
            }
        }
    }
}

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
        scale = 1f
        offsetX = 0f
        offsetY = 0f
        onZoomChanged(false)
    }

    AsyncImage(
        model = model,
        contentDescription = null,
        contentScale = ContentScale.Fit,
        modifier = modifier
            .background(Color.Black)
            .pointerInput(Unit) {
                detectTransformGestures { _, pan, zoom, _ ->
                    val newScale = (scale * zoom).coerceIn(1f, 5f)
                    scale = newScale
                    onZoomChanged(newScale > 1f)
                    if (newScale > 1f) {
                        offsetX += pan.x
                        offsetY += pan.y
                    } else {
                        offsetX = 0f
                        offsetY = 0f
                    }
                }
            }
            .graphicsLayer(
                scaleX = scale,
                scaleY = scale,
                translationX = offsetX,
                translationY = offsetY,
            ),
    )
}
