package com.rekindle.app.ui.screens

import androidx.compose.ui.unit.sp
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.material3.Surface
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.Column
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
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.FontDownload
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.TextDecrease
import androidx.compose.material.icons.filled.TextIncrease
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.hilt.navigation.compose.hiltViewModel
import com.rekindle.app.core.prefs.BookFont
import com.rekindle.app.ui.viewmodel.BookDefinition
import com.rekindle.app.ui.viewmodel.EpubReaderViewModel
import com.rekindle.app.ui.viewmodel.EpubTheme
import com.rekindle.app.ui.viewmodel.theme

@Composable
fun EpubReaderScreen(
    mediaId: String,
    title: String,
    onBack: () -> Unit,
    vm: EpubReaderViewModel = hiltViewModel(),
) {
    val state by vm.state.collectAsState()

    val theme = state.theme(appDark = MaterialTheme.colorScheme.background.luminance() < 0.5f)
    val bgColor = theme.bgColor
    val fgColor = theme.fgColor

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
                val chapter = book.chapters[state.chapterIndex]

                AndroidView(
                    factory = { ctx ->
                        BookWebView(
                            context = ctx,
                            onTap = vm::toggleControls,
                            onLinkToChapter = vm::goToChapter,
                            onPositionChanged = vm::onPositionChanged,
                            onDefine = vm::define,
                            onTouchedPage = vm::dismissDefinition,
                        )
                    },
                    update = { wv ->
                        wv.book = book
                        wv.themeCss = themeCss(theme, state.font)
                        wv.setBackgroundColor(bgColor.toArgb())
                        wv.applyFontSize(state.fontSize)
                        wv.show(chapter.path, "${theme.name}|${state.font.name}", state.startFraction)
                    },
                    // No padding for the HUD: the controls float over the page, because
                    // resizing the page on every tap moved the text being read. The
                    // theme's body padding keeps the chapter's ends clear of them.
                    modifier = Modifier.fillMaxSize(),
                )

                state.definition?.let { definition ->
                    DefinitionCard(
                        definition = definition,
                        background = bgColor,
                        foreground = fgColor,
                        modifier = Modifier
                            .align(Alignment.BottomCenter)
                            .padding(start = 12.dp, end = 12.dp, bottom = if (state.showControls) 64.dp else 16.dp),
                    )
                }

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
                            text = chapter.title,
                            color = fgColor,
                            maxLines = 1,
                            modifier = Modifier.weight(1f),
                        )
                        IconButton(onClick = { vm.cycleTheme(theme) }) {
                            Icon(Icons.Default.Palette, "Theme", tint = fgColor)
                        }
                        IconButton(onClick = vm::cycleFont) {
                            Icon(Icons.Default.FontDownload, "Font: ${state.font.label}", tint = fgColor)
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
                            Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, null, tint = fgColor)
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
                            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = fgColor)
                        }
                    }
                }
            }
        }
    }
}

/**
 * A small card with a word's meanings. It floats over the page without taking focus or
 * moving anything, so the reader's place and flow are untouched.
 */
@Composable
private fun DefinitionCard(
    definition: BookDefinition,
    background: Color,
    foreground: Color,
    modifier: Modifier = Modifier,
) {
    val muted = foreground.copy(alpha = 0.7f)
    Surface(
        modifier = modifier.fillMaxWidth().heightIn(max = 240.dp),
        color = background,
        contentColor = foreground,
        shape = RoundedCornerShape(12.dp),
        shadowElevation = 6.dp,
    ) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(14.dp)) {
            if (definition.entries.isEmpty()) {
                Text("No definition found for \"${definition.word}\".", color = muted)
            }
            definition.entries.forEach { entry ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(entry.word, fontWeight = FontWeight.SemiBold)
                    Spacer(Modifier.width(8.dp))
                    Text(entry.partOfSpeech, color = muted, fontStyle = FontStyle.Italic, fontSize = 13.sp)
                }
                entry.senses.forEachIndexed { i, sense ->
                    Text("${i + 1}. ${sense.definition}", fontSize = 14.sp, modifier = Modifier.padding(top = 2.dp))
                    sense.example?.let {
                        Text("\"$it\"", color = muted, fontStyle = FontStyle.Italic, fontSize = 13.sp)
                    }
                }
                Spacer(Modifier.height(6.dp))
            }
            Text("WordNet", color = muted, fontSize = 11.sp)
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

/**
 * The reader's theme, added after the book's own styles. Colours use !important
 * because books often hard-code black text, which would vanish on the dark theme.
 */
private fun themeCss(theme: EpubTheme, font: BookFont): String {
    val bg = colorHex(theme.bgColor)
    val fg = colorHex(theme.fgColor)
    return """
html, body { background: $bg !important; color: $fg !important; }
body { line-height: 1.6; padding: 64px 16px !important; max-width: 720px;
       margin: 0 auto !important; font-family: serif; box-sizing: border-box; }
body * { color: inherit !important; background-color: transparent !important; }
img, svg { max-width: 100% !important; height: auto; }
${font.css}
"""
}
