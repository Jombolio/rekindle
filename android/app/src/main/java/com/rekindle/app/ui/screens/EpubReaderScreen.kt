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
import androidx.compose.material.icons.filled.TextFormat
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.RecordVoiceOver
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.TextDecrease
import androidx.compose.material.icons.filled.TextIncrease
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.platform.LocalContext
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.widget.Toast
import com.rekindle.app.core.readaloud.ReadAloud
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.IntOffset
import kotlin.math.roundToInt
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.hilt.navigation.compose.hiltViewModel
import com.rekindle.app.core.prefs.BookFont
import com.rekindle.app.core.prefs.BookLayout
import com.rekindle.app.core.prefs.ReadingCss
import com.rekindle.app.ui.viewmodel.BookDefinition
import com.rekindle.app.ui.viewmodel.EpubReaderViewModel
import com.rekindle.app.ui.viewmodel.EpubTheme
import com.rekindle.app.ui.viewmodel.theme

@Composable
@OptIn(ExperimentalMaterial3Api::class)
fun EpubReaderScreen(
    mediaId: String,
    title: String,
    onBack: () -> Unit,
    vm: EpubReaderViewModel = hiltViewModel(),
) {
    val state by vm.state.collectAsState()
    var webView by remember { mutableStateOf<BookWebView?>(null) }
    val layout = state.style.layout
    val context = LocalContext.current

    LaunchedEffect(vm) {
        vm.messages.collect { Toast.makeText(context, it, Toast.LENGTH_LONG).show() }
    }

    // Reading aloud carries on with the screen off, with its controls in a
    // notification, which Android 13 and later ask permission to show. Reading works
    // either way, so it's asked once and not insisted on.
    var askedNotifications by rememberSaveable { mutableStateOf(false) }
    val notificationPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {}
    fun startReadAloud() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && !askedNotifications &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            askedNotifications = true
            notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
        webView?.sentenceInView { chapter, sentence -> vm.readAloudFrom(chapter, sentence) }
    }

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
                            onPage = vm::onPage,
                            onFlowPosition = vm::onFlowPosition,
                            onPastEnd = vm::onPastEnd,
                            onBeforeStart = vm::onBeforeStart,
                            onReadAloudFrom = vm::readAloudFrom,
                        ).also { webView = it }
                    },
                    update = { wv ->
                        wv.book = book
                        wv.layout = layout
                        wv.animations = state.style.animations
                        wv.turnMs = state.pageTurnMs
                        wv.themeCss = themeCss(theme, state.font) + ReadingCss.css(state.style)
                        wv.setBackgroundColor(bgColor.toArgb())
                        wv.applyFontSize(state.fontSize)
                        wv.show(
                            chapterIndex = if (layout == BookLayout.CONTINUOUS) state.flowStart else state.chapterIndex,
                            styleKey = "${theme.name}|${state.font.name}|${state.style.toJson()}",
                            startFraction = state.startFraction,
                        )
                        wv.highlightSentence(state.readingChapter, state.readingSentence)
                    },
                    // No padding for the HUD: the controls float over the page, because
                    // resizing the page on every tap moved the text being read. The
                    // theme's body padding keeps the chapter's ends clear of them.
                    modifier = Modifier.fillMaxSize(),
                )

                if (state.style.ruler) {
                    ReadingRuler(
                        bandHeightDp = state.fontSize * state.style.lineHeight * 1.5f,
                        shade = bgColor,
                        edge = fgColor,
                    )
                }

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
                        ReadAloudButtons(
                            status = state.readAloud,
                            tint = fgColor,
                            onStart = ::startReadAloud,
                            onPauseOrResume = vm::pauseOrResumeReadAloud,
                            onStop = vm::stopReadAloud,
                        )
                        IconButton(onClick = { vm.cycleTheme(theme) }) {
                            Icon(Icons.Default.Palette, "Theme", tint = fgColor)
                        }
                        IconButton(onClick = vm::decreaseFontSize) {
                            Icon(Icons.Default.TextDecrease, "Smaller text", tint = fgColor)
                        }
                        IconButton(onClick = vm::increaseFontSize) {
                            Icon(Icons.Default.TextIncrease, "Larger text", tint = fgColor)
                        }
                        IconButton(onClick = { vm.showOptions(true) }) {
                            Icon(Icons.Default.TextFormat, "Reading options", tint = fgColor)
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
                        val perScreen = if (layout == BookLayout.SPREAD) 2 else 1
                        IconButton(
                            onClick = { if (layout.paged) webView?.previousPage() else vm.prevChapter() },
                            enabled = state.chapterIndex > 0 || (layout.paged && state.page > 0),
                        ) {
                            Icon(
                                Icons.AutoMirrored.Filled.KeyboardArrowLeft,
                                if (layout.paged) "Previous page" else "Previous chapter",
                                tint = fgColor,
                            )
                        }
                        Spacer(Modifier.weight(1f))
                        Text(
                            text = positionLabel(state.chapterIndex, book.chapters.size, layout, state.page, state.pageCount),
                            color = fgColor,
                        )
                        Spacer(Modifier.weight(1f))
                        IconButton(
                            onClick = { if (layout.paged) webView?.nextPage() else vm.nextChapter() },
                            enabled = state.chapterIndex < book.chapters.size - 1 ||
                                (layout.paged && state.page + perScreen < state.pageCount),
                        ) {
                            Icon(
                                Icons.AutoMirrored.Filled.KeyboardArrowRight,
                                if (layout.paged) "Next page" else "Next chapter",
                                tint = fgColor,
                            )
                        }
                    }
                }

                if (state.showOptions) {
                    ModalBottomSheet(
                        onDismissRequest = { vm.showOptions(false) },
                        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
                    ) {
                        ReadingOptions(
                            style = state.style,
                            font = state.font,
                            fontSize = state.fontSize,
                            theme = state.defaultTheme,
                            onStyle = vm::setStyle,
                            onFont = vm::setFont,
                            onFontSize = vm::setFontSizeTo,
                            onTheme = vm::setDefaultTheme,
                            modifier = Modifier
                                .verticalScroll(rememberScrollState())
                                .padding(start = 20.dp, end = 20.dp, bottom = 32.dp),
                            readAloud = { ReadAloudOptions() },
                        )
                    }
                }
            }
        }
    }
}

/** Read aloud from the page on screen; then pause, resume and stop. */
@Composable
private fun ReadAloudButtons(
    status: ReadAloud.Status,
    tint: Color,
    onStart: () -> Unit,
    onPauseOrResume: () -> Unit,
    onStop: () -> Unit,
) {
    when (status) {
        ReadAloud.Status.IDLE -> IconButton(onClick = onStart) {
            Icon(Icons.Default.RecordVoiceOver, "Read aloud", tint = tint)
        }
        ReadAloud.Status.STARTING -> IconButton(onClick = onStop) {
            CircularProgressIndicator(Modifier.size(20.dp), color = tint, strokeWidth = 2.dp)
        }
        ReadAloud.Status.PLAYING, ReadAloud.Status.PAUSED -> {
            IconButton(onClick = onPauseOrResume) {
                if (status == ReadAloud.Status.PLAYING) Icon(Icons.Default.Pause, "Pause reading aloud", tint = tint)
                else Icon(Icons.Default.PlayArrow, "Resume reading aloud", tint = tint)
            }
            IconButton(onClick = onStop) {
                Icon(Icons.Default.Stop, "Stop reading aloud", tint = tint)
            }
        }
    }
}

private fun positionLabel(chapter: Int, chapters: Int, layout: BookLayout, page: Int, pageCount: Int): String {
    val base = "Chapter ${chapter + 1} / $chapters"
    if (!layout.paged || pageCount <= 0) return base
    // A spread's left page is -1 when a chapter opens alone on the right.
    val first = if (page < 0) 1 else page + 1
    val last = if (layout == BookLayout.SPREAD) minOf(page + 2, pageCount) else first
    val pages = if (first == last) "Page $first" else "Pages $first–$last"
    return "$base · $pages of $pageCount"
}

/**
 * A band to keep the reader's place, with the rest of the page dimmed. It stays
 * where it's put while the text moves under it; the handle on its right moves it.
 */
@Composable
private fun ReadingRuler(bandHeightDp: Float, shade: Color, edge: Color) {
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val density = LocalDensity.current
        val heightPx = constraints.maxHeight.toFloat()
        val widthPx = constraints.maxWidth
        val bandPx = with(density) { bandHeightDp.dp.toPx() }
        var centre by remember { mutableFloatStateOf(heightPx * 0.4f) }
        Canvas(Modifier.fillMaxSize()) {
            val top = (centre - bandPx / 2).coerceIn(0f, size.height)
            val bottom = (centre + bandPx / 2).coerceIn(0f, size.height)
            val dim = shade.copy(alpha = 0.6f)
            drawRect(dim, Offset.Zero, Size(size.width, top))
            drawRect(dim, Offset(0f, bottom), Size(size.width, size.height - bottom))
            drawLine(edge.copy(alpha = 0.35f), Offset(0f, top), Offset(size.width, top), strokeWidth = 2f)
            drawLine(edge.copy(alpha = 0.35f), Offset(0f, bottom), Offset(size.width, bottom), strokeWidth = 2f)
        }
        val handle = 36.dp
        val handlePx = with(density) { handle.toPx() }
        Box(
            Modifier
                .offset { IntOffset(widthPx - handlePx.roundToInt(), (centre - handlePx / 2).roundToInt()) }
                .size(handle)
                .background(edge.copy(alpha = 0.25f), CircleShape)
                .draggable(
                    orientation = Orientation.Vertical,
                    state = rememberDraggableState { delta -> centre = (centre + delta).coerceIn(0f, heightPx) },
                ),
        )
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
        EpubTheme.CONTRAST_DARK -> Color.Black
        EpubTheme.CONTRAST_LIGHT -> Color.White
    }

private val EpubTheme.fgColor: Color
    get() = when (this) {
        EpubTheme.LIGHT -> Color(0xFF1A1A1A)
        EpubTheme.DARK -> Color(0xFFE0E0E0)
        EpubTheme.SEPIA -> Color(0xFF3B2C1A)
        EpubTheme.CONTRAST_DARK -> Color.White
        EpubTheme.CONTRAST_LIGHT -> Color.Black
    }

/** The sentence being read aloud: the text's own colour, faint, as on desktop. */
private fun highlightCss(fg: Color): String {
    val argb = fg.toArgb()
    return "rgba(${(argb shr 16) and 0xFF},${(argb shr 8) and 0xFF},${argb and 0xFF},0.2)"
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
body { font-family: serif; }
body * { color: inherit !important; background-color: transparent !important; }
body .$READ_ALOUD_HIGHLIGHT { background-color: ${highlightCss(theme.fgColor)} !important; border-radius: 2px; }
img, svg { max-width: 100% !important; height: auto; }
${font.css}
"""
}
