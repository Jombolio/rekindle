package com.rekindle.app.ui.screens

import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.KeyboardArrowLeft
import androidx.compose.material.icons.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.TextDecrease
import androidx.compose.material.icons.filled.TextIncrease
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.hilt.navigation.compose.hiltViewModel
import com.rekindle.app.ui.viewmodel.EpubReaderState
import com.rekindle.app.ui.viewmodel.EpubReaderViewModel
import com.rekindle.app.ui.viewmodel.EpubTheme

@Composable
fun EpubReaderScreen(
    mediaId: String,
    title: String,
    onBack: () -> Unit,
    vm: EpubReaderViewModel = hiltViewModel(),
) {
    val state by vm.state.collectAsState()

    val bgColor = state.theme.bgColor
    val fgColor = state.theme.fgColor

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(bgColor)
            .clickable(onClick = vm::toggleControls),
    ) {
        when {
            state.error != null -> {
                Text(
                    text = state.error!!,
                    color = fgColor,
                    modifier = Modifier.align(Alignment.Center).padding(24.dp),
                )
            }

            state.book == null -> {
                CircularProgressIndicator(modifier = Modifier.align(Alignment.Center))
            }

            else -> {
                val book = state.book!!
                val chapterHtml = book.chapters[state.chapterIndex].html
                val styledHtml = wrapHtml(chapterHtml, state)

                AndroidView(
                    factory = { ctx ->
                        WebView(ctx).apply {
                            webViewClient = WebViewClient()
                            settings.javaScriptEnabled = false
                            setBackgroundColor(bgColor.toArgb())
                        }
                    },
                    update = { wv ->
                        wv.setBackgroundColor(bgColor.toArgb())
                        wv.loadDataWithBaseURL(null, styledHtml, "text/html", "utf-8", null)
                    },
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(top = if (state.showControls) 56.dp else 0.dp,
                            bottom = if (state.showControls) 56.dp else 0.dp),
                )

                if (state.showControls) {
                    // Top bar
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .align(Alignment.TopStart)
                            .background(bgColor.copy(alpha = 0.95f))
                            .padding(horizontal = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        IconButton(onClick = onBack) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, null, tint = fgColor)
                        }
                        Text(
                            text = book.chapters[state.chapterIndex].title,
                            color = fgColor,
                            maxLines = 1,
                            modifier = Modifier.weight(1f),
                        )
                        IconButton(onClick = vm::cycleTheme) {
                            Icon(Icons.Default.Palette, "Cycle theme", tint = fgColor)
                        }
                        IconButton(onClick = vm::decreaseFontSize) {
                            Icon(Icons.Default.TextDecrease, "Decrease font", tint = fgColor)
                        }
                        IconButton(onClick = vm::increaseFontSize) {
                            Icon(Icons.Default.TextIncrease, "Increase font", tint = fgColor)
                        }
                    }

                    // Bottom chapter nav
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .align(Alignment.BottomStart)
                            .background(bgColor.copy(alpha = 0.95f))
                            .padding(horizontal = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        IconButton(
                            onClick = vm::prevChapter,
                            enabled = state.chapterIndex > 0,
                        ) {
                            Icon(Icons.Default.KeyboardArrowLeft, null, tint = fgColor)
                        }
                        Spacer(Modifier.weight(1f))
                        Text(
                            text = "Chapter ${state.chapterIndex + 1} / ${book.chapters.size}",
                            color = fgColor,
                        )
                        Spacer(Modifier.weight(1f))
                        IconButton(
                            onClick = vm::nextChapter,
                            enabled = state.chapterIndex < book.chapters.size - 1,
                        ) {
                            Icon(Icons.Default.KeyboardArrowRight, null, tint = fgColor)
                        }
                    }
                }
            }
        }
    }
}

private val EpubTheme.bgColor: Color
    get() = when (this) {
        EpubTheme.LIGHT -> Color.White
        EpubTheme.DARK -> Color(0xFF1A1A1A)
        EpubTheme.SEPIA -> Color(0xFFF5ECD7)
    }

private val EpubTheme.fgColor: Color
    get() = when (this) {
        EpubTheme.LIGHT -> Color(0xFF1A1A1A)
        EpubTheme.DARK -> Color(0xFFE0E0E0)
        EpubTheme.SEPIA -> Color(0xFF3B2C1A)
    }

private fun colorHex(color: Color): String {
    val argb = color.toArgb()
    return "#%06X".format(argb and 0xFFFFFF)
}

private fun wrapHtml(html: String, state: EpubReaderState): String {
    val bg = colorHex(state.theme.bgColor)
    val fg = colorHex(state.theme.fgColor)
    val fs = state.fontSize.toInt()
    return """<!DOCTYPE html>
<html><head><meta name="viewport" content="width=device-width,initial-scale=1">
<style>
body { background:$bg; color:$fg; font-size:${fs}px; line-height:1.6;
       padding:16px; max-width:720px; margin:0 auto; font-family:serif; }
img { max-width:100%; }
</style></head><body>
${extractBody(html)}
</body></html>"""
}

private fun extractBody(html: String): String {
    val bodyRegex = Regex("<body[^>]*>(.*?)</body>", RegexOption.DOT_MATCHES_ALL)
    return bodyRegex.find(html)?.groupValues?.get(1) ?: html
}
