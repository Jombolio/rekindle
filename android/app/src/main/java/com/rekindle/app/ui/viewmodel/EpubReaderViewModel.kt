package com.rekindle.app.ui.viewmodel

import android.content.Context
import android.net.Uri
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.rekindle.app.core.epub.EpubBook
import com.rekindle.app.core.epub.EpubParser
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
    val book: EpubBook? = null,
    val chapterIndex: Int = 0,
    /** Where to place the view on entering [chapterIndex]. Doesn't follow scrolling. */
    val startFraction: Float = 0f,
    val fontSize: Float = 16f,
    val theme: EpubTheme = EpubTheme.LIGHT,
    val showControls: Boolean = true,
    val error: String? = null,
)

enum class EpubTheme { LIGHT, DARK, SEPIA }

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
            loadProgress()
            loadEpub()
        }
    }

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
            val book = withContext(Dispatchers.IO) { EpubParser.open(obtainBookFile()) }
            if (book.chapters.isEmpty()) {
                // Publishing the book anyway would crash the screen on chapters[0].
                book.close()
                _state.update { it.copy(error = "This book contains no readable chapters.") }
                return
            }
            val chapter = savedChapter.coerceIn(0, book.chapters.size - 1)
            fraction = savedFraction
            _state.update { it.copy(book = book, chapterIndex = chapter, startFraction = savedFraction) }
            // Lets the server record the chapter count, which it needs to show a
            // percentage on the cover. Purely informational, so failure is fine.
            runCatching { mediaRepo.getPageCount(mediaId) }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            _state.update { it.copy(error = describeLoadFailure(e)) }
        }
    }

    /** The downloaded copy when there's a usable one, otherwise fetched from the server. */
    private suspend fun obtainBookFile(): File {
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
            if (EpubParser.isEpubFile(local)) return local
        }

        sessionFile.parentFile?.mkdirs()
        val temp = File(sessionFile.path + ".tmp")
        try {
            mediaRepo.getBook(mediaId).use { body ->
                temp.outputStream().use { body.byteStream().copyTo(it) }
            }
            if (!temp.renameTo(sessionFile)) {
                temp.copyTo(sessionFile, overwrite = true)
            }
        } finally {
            temp.delete()
        }
        return sessionFile
    }

    private fun describeLoadFailure(e: Exception): String = when (e) {
        is HttpException -> if (e.code() == 403) {
            "Your account doesn't have permission to open this book."
        } else {
            // 422 carries the server's explanation, e.g. a DRM-protected MOBI.
            val reason = if (e.code() == 422) {
                runCatching {
                    JSONObject(e.response()?.errorBody()?.string().orEmpty()).getString("error")
                }.getOrNull()
            } else null
            reason ?: "This book couldn't be opened."
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

    fun goToChapter(index: Int) {
        val book = _state.value.book ?: return
        if (index !in book.chapters.indices || index == _state.value.chapterIndex) return
        fraction = 0f
        moved = true
        _state.update { it.copy(chapterIndex = index, startFraction = 0f) }
        saveSoon(immediately = true)
    }

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

    fun increaseFontSize() = _state.update { it.copy(fontSize = (it.fontSize + 1f).coerceAtMost(32f)) }
    fun decreaseFontSize() = _state.update { it.copy(fontSize = (it.fontSize - 1f).coerceAtLeast(10f)) }

    fun cycleTheme() = _state.update {
        val next = EpubTheme.entries[(it.theme.ordinal + 1) % EpubTheme.entries.size]
        it.copy(theme = next)
    }

    fun toggleControls() = _state.update { it.copy(showControls = !it.showControls) }

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
