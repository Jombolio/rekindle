package com.rekindle.app.ui.viewmodel

import android.content.Context
import android.net.Uri
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.rekindle.app.core.dictionary.DictionaryEntry
import com.rekindle.app.core.dictionary.WordForms
import com.rekindle.app.core.dictionary.WordNetDictionary
import com.rekindle.app.core.epub.EpubParser
import com.rekindle.app.core.epub.ReaderBook
import com.rekindle.app.core.prefs.BookFont
import com.rekindle.app.core.prefs.BookLayout
import com.rekindle.app.core.prefs.BookTheme
import com.rekindle.app.core.prefs.DEFAULT_BOOK_FONT_SIZE
import com.rekindle.app.core.prefs.DEFAULT_PAGE_TURN_MS
import com.rekindle.app.core.prefs.MAX_BOOK_FONT_SIZE
import com.rekindle.app.core.prefs.MIN_BOOK_FONT_SIZE
import com.rekindle.app.core.prefs.PrefsStore
import com.rekindle.app.core.prefs.ReadingStyle
import com.rekindle.app.data.repository.DownloadRepository
import com.rekindle.app.data.repository.MediaRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import retrofit2.HttpException
import java.io.File
import java.io.IOException
import java.util.UUID
import javax.inject.Inject

data class EpubReaderState(
    val book: ReaderBook? = null,
    val chapterIndex: Int = 0,
    /** Where to place the view on entering [chapterIndex]. Doesn't follow scrolling. */
    val startFraction: Float = 0f,
    val fontSize: Float = DEFAULT_BOOK_FONT_SIZE,
    val font: BookFont = BookFont.ORIGINAL,
    /** The theme from Settings, until the palette button picks one for this visit. */
    val defaultTheme: BookTheme = BookTheme.MATCH_APP,
    val themeOverride: EpubTheme? = null,
    /** Layout and readability options. */
    val style: ReadingStyle = ReadingStyle(),
    /** How long one page turn takes, in milliseconds. */
    val pageTurnMs: Int = DEFAULT_PAGE_TURN_MS,
    /**
     * Where the continuous layout's document starts. It changes only when the reader
     * jumps to a chapter; scrolling into the next one moves [chapterIndex] alone.
     */
    val flowStart: Int = 0,
    /** In the paged layouts: the page shown (the left one of a spread), and how many. */
    val page: Int = 0,
    val pageCount: Int = 0,
    val showOptions: Boolean = false,
    val showControls: Boolean = true,
    /** The dictionary pop-up, when one is open. */
    val definition: BookDefinition? = null,
    val error: String? = null,
)

enum class EpubTheme { LIGHT, DARK, SEPIA, CONTRAST_DARK, CONTRAST_LIGHT }

/** The theme to read in, given whether the app itself is dark. */
fun EpubReaderState.theme(appDark: Boolean): EpubTheme = themeOverride ?: when (defaultTheme) {
    BookTheme.MATCH_APP -> if (appDark) EpubTheme.DARK else EpubTheme.LIGHT
    BookTheme.LIGHT -> EpubTheme.LIGHT
    BookTheme.DARK -> EpubTheme.DARK
    BookTheme.SEPIA -> EpubTheme.SEPIA
    BookTheme.CONTRAST_DARK -> EpubTheme.CONTRAST_DARK
    BookTheme.CONTRAST_LIGHT -> EpubTheme.CONTRAST_LIGHT
}

data class BookDefinition(val word: String, val entries: List<DictionaryEntry>)

/**
 * A book is finished once the reader is at the end of its last chapter. Merely
 * opening the last chapter doesn't count, and neither does being a little short of
 * the very bottom, which scrolling doesn't always reach.
 */
fun isBookFinished(chapter: Int, chapterCount: Int, fraction: Float): Boolean =
    chapter >= chapterCount - 1 && fraction >= 0.97f

@HiltViewModel
class EpubReaderViewModel @Inject constructor(
    @ApplicationContext private val context: Context,
    savedStateHandle: SavedStateHandle,
    private val downloadRepo: DownloadRepository,
    private val mediaRepo: MediaRepository,
    private val prefs: PrefsStore,
    private val dictionary: WordNetDictionary,
) : ViewModel() {

    private val mediaId: String = checkNotNull(savedStateHandle["mediaId"])

    private val _state = MutableStateFlow(EpubReaderState())
    val state = _state.asStateFlow()

    /** The current spot. Kept out of [state]: it changes on every scroll tick. */
    private var fraction = 0f
    private var savedChapter = 0
    private var savedFraction = 0f
    private var wasCompletedOnLoad = false
    private var moved = false
    private var saveJob: Job? = null

    /** A copy for this session only, deleted on close. Downloads aren't touched. */
    private val sessionFile = File(context.cacheDir, "books/$mediaId-${UUID.randomUUID()}.epub")

    init {
        viewModelScope.launch {
            val font = prefs.bookFont.first()
            val size = prefs.bookFontSize.first()
            val theme = prefs.bookTheme.first()
            val style = prefs.readingStyle.first()
            _state.update { it.copy(font = font, fontSize = size, defaultTheme = theme, style = style) }
            loadProgress()
            loadEpub()
            followSettings()
        }
    }

    /**
     * Applies changes from the options panel or Settings as they're made. A change
     * that reflows the text reopens it at the current spot.
     */
    private fun followSettings() {
        // On its own: how long a turn takes never reflows the text.
        viewModelScope.launch {
            prefs.pageTurnMs.collect { ms -> _state.update { it.copy(pageTurnMs = ms) } }
        }
        viewModelScope.launch {
            combine(prefs.bookFont, prefs.bookFontSize, prefs.bookTheme, prefs.readingStyle) { font, size, theme, style ->
                Settings(font, size, theme, style)
            }.collect { next ->
                _state.update {
                    val reflows = it.font != next.font || it.style != next.style || it.defaultTheme != next.theme
                    it.copy(
                        font = next.font,
                        fontSize = next.size,
                        defaultTheme = next.theme,
                        style = next.style,
                        startFraction = if (reflows) fraction else it.startFraction,
                        flowStart = if (reflows) it.chapterIndex else it.flowStart,
                    )
                }
            }
        }
    }

    private data class Settings(val font: BookFont, val size: Float, val theme: BookTheme, val style: ReadingStyle)

    private suspend fun loadProgress() {
        val progress = mediaRepo.getProgress(mediaId)
        // Completed books restart at the beginning — matches the image reader and the
        // documented cross-client invariant (now reachable offline via the local fallback).
        wasCompletedOnLoad = progress?.isCompleted == true
        if (!wasCompletedOnLoad) {
            savedChapter = progress?.currentPage ?: 0
            savedFraction = progress?.positionFraction?.toFloat() ?: 0f
        }
    }

    private suspend fun loadEpub() {
        try {
            val book = withContext(Dispatchers.IO) { openBook() }
            if (book.chapters.isEmpty()) {
                // Publishing the book anyway would crash the screen on chapters[0].
                book.close()
                _state.update { it.copy(error = "This book contains no readable chapters.") }
                return
            }
            val chapter = savedChapter.coerceIn(0, book.chapters.size - 1)
            fraction = savedFraction
            _state.update {
                it.copy(book = book, chapterIndex = chapter, flowStart = chapter, startFraction = savedFraction)
            }
            // Lets the server record the chapter count, which it needs to show a
            // percentage on the cover. Purely informational, so failure is fine.
            runCatching { mediaRepo.getPageCount(mediaId) }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            _state.update { it.copy(error = describeLoadFailure(e)) }
        }
    }

    /** The downloaded copy when there's a usable one, otherwise streamed from the server. */
    private suspend fun openBook(): ReaderBook {
        // awaitState (not stateFor) restores from disk if the in-memory map is cold,
        // so opening a downloaded book offline doesn't falsely report "not downloaded".
        val localPath = downloadRepo.awaitState(mediaId).localPath
        if (localPath != null) {
            val local = if (localPath.startsWith("content://")) {
                // ZipFile needs a real file, and a SAF document isn't one.
                sessionFile.parentFile?.mkdirs()
                context.contentResolver.openInputStream(Uri.parse(localPath))?.use { input ->
                    sessionFile.outputStream().use { input.copyTo(it) }
                }
                sessionFile
            } else {
                File(localPath)
            }
            if (EpubParser.isEpubFile(local)) return EpubParser.open(local)
        }
        return mediaRepo.openRemoteBook(mediaId)
    }

    private fun describeLoadFailure(e: Exception): String = when (e) {
        is HttpException -> when (e.code()) {
            404 -> "Your server needs updating to read this book without downloading it."
            // 422 carries the server's explanation, e.g. a DRM-protected Kindle file.
            422 -> runCatching {
                JSONObject(e.response()?.errorBody()?.string().orEmpty()).getString("error")
            }.getOrNull() ?: "This book couldn't be opened."
            else -> "This book couldn't be opened."
        }
        is IOException -> "Couldn't reach the server. Connect, or download this book to read it offline."
        else -> "This book couldn't be opened."
    }

    fun nextChapter() {
        val book = _state.value.book ?: return
        if (_state.value.chapterIndex < book.chapters.size - 1) goToChapter(_state.value.chapterIndex + 1)
    }

    fun prevChapter() {
        if (_state.value.chapterIndex > 0) goToChapter(_state.value.chapterIndex - 1)
    }

    /** Opens chapter [index] at [at]: 0 is its start, 1 its last page. */
    fun goToChapter(index: Int) = goToChapter(index, at = 0f)

    fun goToChapter(index: Int, at: Float) {
        val book = _state.value.book ?: return
        if (index !in book.chapters.indices) return
        // In the continuous layout the chapter being read can already be [index]
        // while the document starts elsewhere, so a jump there still moves.
        val s = _state.value
        val continuous = s.style.layout == BookLayout.CONTINUOUS
        if (index == s.chapterIndex && (!continuous || index == s.flowStart)) return
        fraction = at
        moved = true
        _state.update { it.copy(chapterIndex = index, flowStart = index, startFraction = at, page = 0, pageCount = 0) }
        saveSoon(immediately = true)
    }

    /** Paged layouts: the page shown changed. [turned] is the reader turning it. */
    fun onPage(page: Int, count: Int, pageFraction: Float, turned: Boolean) {
        _state.update { if (it.page == page && it.pageCount == count) it else it.copy(page = page, pageCount = count) }
        if (!turned) return
        fraction = pageFraction
        moved = true
        saveSoon(immediately = false)
    }

    /** Continuous layout: the chapter under the reading line, and how far into it. */
    fun onFlowPosition(chapter: Int, chapterFraction: Float) {
        if (chapter != _state.value.chapterIndex) _state.update { it.copy(chapterIndex = chapter) }
        onPositionChanged(chapterFraction)
    }

    /** Turned past a chapter's last page. */
    fun onPastEnd() = nextChapter()

    /** Turned back from a chapter's first page: the previous chapter's last. */
    fun onBeforeStart() {
        val index = _state.value.chapterIndex
        if (index > 0) goToChapter(index - 1, at = 1f)
    }

    fun setStyle(style: ReadingStyle) {
        viewModelScope.launch { prefs.setReadingStyle(style) }
    }

    fun setFont(font: BookFont) {
        viewModelScope.launch { prefs.setBookFont(font) }
    }

    fun setFontSizeTo(size: Float) = setFontSize(size.coerceIn(MIN_BOOK_FONT_SIZE, MAX_BOOK_FONT_SIZE))

    /** Changes the default theme, and drops one picked with the palette for this visit. */
    fun setDefaultTheme(theme: BookTheme) {
        _state.update { it.copy(themeOverride = null) }
        viewModelScope.launch { prefs.setBookTheme(theme) }
    }

    fun showOptions(show: Boolean) = _state.update { it.copy(showOptions = show) }

    /** Called as the reader scrolls. Saves once scrolling has paused. */
    fun onPositionChanged(newFraction: Float) {
        if (kotlin.math.abs(newFraction - fraction) < 0.001f) return
        fraction = newFraction
        moved = true
        saveSoon(immediately = false)
    }

    private fun saveSoon(immediately: Boolean) {
        saveJob?.cancel()
        saveJob = viewModelScope.launch {
            if (!immediately) delay(SAVE_DEBOUNCE_MS)
            persist()
            // Refreshing covers on every chapter flip was already the behaviour here;
            // scroll saves leave that to the exit-time sync.
            mediaRepo.syncProgress(mediaId, notifyCovers = immediately)
        }
    }

    private suspend fun persist() {
        val s = _state.value
        val book = s.book ?: return
        mediaRepo.saveProgress(
            mediaId = mediaId,
            currentPage = s.chapterIndex,
            isCompleted = isBookFinished(s.chapterIndex, book.chapters.size, fraction),
            positionFraction = fraction.toDouble(),
        )
    }

    fun increaseFontSize() = setFontSize((_state.value.fontSize + 1f).coerceAtMost(MAX_BOOK_FONT_SIZE))
    fun decreaseFontSize() = setFontSize((_state.value.fontSize - 1f).coerceAtLeast(MIN_BOOK_FONT_SIZE))

    private fun setFontSize(size: Float) {
        _state.update { it.copy(fontSize = size) }
        viewModelScope.launch { prefs.setBookFontSize(size) }
    }

    /** Moves on from [current], the theme on screen, for this visit only. */
    fun cycleTheme(current: EpubTheme) = _state.update {
        it.copy(
            themeOverride = EpubTheme.entries[(current.ordinal + 1) % EpubTheme.entries.size],
            // The page reloads in the new colours, at the current spot.
            startFraction = fraction,
            flowStart = it.chapterIndex,
        )
    }

    fun toggleControls() = _state.update { it.copy(showControls = !it.showControls) }

    private var defineJob: Job? = null

    fun define(selection: String) {
        val word = WordForms.normalize(selection) ?: return
        defineJob?.cancel()
        defineJob = viewModelScope.launch {
            // A missing definition should never interrupt reading.
            val entries = runCatching { dictionary.lookup(selection) }
                .onFailure { if (it is CancellationException) throw it }
                .getOrDefault(emptyList())
            _state.update { it.copy(definition = BookDefinition(word, entries)) }
        }
    }

    fun dismissDefinition() {
        defineJob?.cancel()
        _state.update { if (it.definition == null) it else it.copy(definition = null) }
    }

    override fun onCleared() {
        super.onCleared()
        val book = _state.value.book
        // viewModelScope is cancelled BEFORE onCleared is invoked, so a coroutine
        // launched on it never runs — the exit-time work needs its own scope.
        CoroutineScope(SupervisorJob() + Dispatchers.IO).launch {
            try {
                // Glancing at a book must not rewrite its progress, least of all a
                // finished book's "Read" state.
                if (book != null && moved) {
                    persist()
                    mediaRepo.syncProgress(mediaId, notifyCovers = true)
                }
            } finally {
                runCatching { book?.close() }
                sessionFile.delete()
            }
        }
    }

    private companion object {
        const val SAVE_DEBOUNCE_MS = 1500L
    }
}
