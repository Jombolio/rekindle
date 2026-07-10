package com.rekindle.app.ui.viewmodel

import android.content.Context
import android.net.Uri
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.rekindle.app.core.epub.EpubBook
import com.rekindle.app.core.epub.EpubParser
import com.rekindle.app.core.prefs.PrefsStore
import com.rekindle.app.data.repository.DownloadRepository
import com.rekindle.app.data.repository.MediaRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import javax.inject.Inject

data class EpubReaderState(
    val book: EpubBook? = null,
    val chapterIndex: Int = 0,
    val fontSize: Float = 16f,
    val theme: EpubTheme = EpubTheme.LIGHT,
    val showControls: Boolean = true,
    val error: String? = null,
)

enum class EpubTheme { LIGHT, DARK, SEPIA }

@HiltViewModel
class EpubReaderViewModel @Inject constructor(
    @ApplicationContext private val context: Context,
    savedStateHandle: SavedStateHandle,
    private val downloadRepo: DownloadRepository,
    private val mediaRepo: MediaRepository,
    private val prefs: PrefsStore,
) : ViewModel() {

    private val mediaId: String = checkNotNull(savedStateHandle["mediaId"])

    private val _state = MutableStateFlow(EpubReaderState())
    val state = _state.asStateFlow()

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
        val chapter = if (progress?.isCompleted == true) 0 else progress?.currentPage ?: 0
        _state.update { it.copy(chapterIndex = chapter) }
    }

    private suspend fun loadEpub() {
        // awaitState (not stateFor) restores from disk if the in-memory map is cold,
        // so opening a downloaded EPUB offline doesn't falsely report "not downloaded".
        val localPath = downloadRepo.awaitState(mediaId).localPath
            ?: run {
                _state.update { it.copy(error = "EPUB not downloaded. Download it first.") }
                return
            }
        runCatching {
            val book = withContext(Dispatchers.IO) {
                val stream = if (localPath.startsWith("content://")) {
                    context.contentResolver.openInputStream(Uri.parse(localPath))
                        ?: error("Cannot open content URI: $localPath")
                } else {
                    File(localPath).inputStream()
                }
                stream.use { EpubParser.parse(it) }
            }
            if (book.chapters.isEmpty()) {
                // Publishing the book anyway would crash the screen on chapters[0].
                _state.update { it.copy(error = "This EPUB contains no readable chapters.") }
                return
            }
            val savedChapter = _state.value.chapterIndex.coerceIn(0, book.chapters.size - 1)
            _state.update { it.copy(book = book, chapterIndex = savedChapter) }
        }.onFailure { e ->
            _state.update { it.copy(error = e.message ?: "Failed to open EPUB.") }
        }
    }

    fun nextChapter() {
        val book = _state.value.book ?: return
        if (_state.value.chapterIndex < book.chapters.size - 1) {
            _state.update { it.copy(chapterIndex = it.chapterIndex + 1) }
            saveChapter()
        }
    }

    fun prevChapter() {
        if (_state.value.chapterIndex > 0) {
            _state.update { it.copy(chapterIndex = it.chapterIndex - 1) }
            saveChapter()
        }
    }

    fun increaseFontSize() = _state.update { it.copy(fontSize = (it.fontSize + 1f).coerceAtMost(32f)) }
    fun decreaseFontSize() = _state.update { it.copy(fontSize = (it.fontSize - 1f).coerceAtLeast(10f)) }

    fun cycleTheme() = _state.update {
        val next = EpubTheme.entries[(it.theme.ordinal + 1) % EpubTheme.entries.size]
        it.copy(theme = next)
    }

    fun toggleControls() = _state.update { it.copy(showControls = !it.showControls) }

    private fun saveChapter() {
        viewModelScope.launch {
            val book = _state.value.book ?: return@launch
            val chapter = _state.value.chapterIndex
            mediaRepo.saveProgress(mediaId, chapter, chapter >= book.chapters.size - 1)
            mediaRepo.syncProgress(mediaId)
        }
    }
}
