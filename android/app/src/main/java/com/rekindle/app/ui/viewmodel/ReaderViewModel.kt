package com.rekindle.app.ui.viewmodel

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.rekindle.app.core.prefs.PrefsStore
import com.rekindle.app.data.repository.DownloadRepository
import com.rekindle.app.data.repository.MediaRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class ReaderState(
    val title: String = "",
    val totalPages: Int = 0,
    val currentPage: Int = 0,
    val initialPage: Int = 0,
    val isRtl: Boolean = false,
    val doublePage: Boolean = false,
    val showControls: Boolean = true,
    val seekToPage: Int = -1,
    /** Non-null when reading from extracted local files. */
    val extractedPages: List<String>? = null,
)

@HiltViewModel
class ReaderViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val repo: MediaRepository,
    private val downloadRepo: DownloadRepository,
    private val prefs: PrefsStore,
) : ViewModel() {

    private val mediaId: String = checkNotNull(savedStateHandle["mediaId"])

    private val _state = MutableStateFlow(ReaderState())
    val state = _state.asStateFlow()

    var authHeader: String = ""
        private set
    private var baseUrl: String = ""

    private var syncJob: Job? = null

    init {
        viewModelScope.launch {
            authHeader = "Bearer ${prefs.token.first() ?: ""}"
            baseUrl = prefs.serverUrl.first()
            _state.update {
                it.copy(
                    isRtl = prefs.isRtl(mediaId).first(),
                    doublePage = prefs.isDoublePage(mediaId).first(),
                )
            }
            loadExtractedPages()
            loadProgress()
            loadPageCount()
        }
    }

    private fun loadExtractedPages() {
        val pages = downloadRepo.extractedPages(mediaId)
        if (pages != null) _state.update { it.copy(extractedPages = pages) }
    }

    private suspend fun loadProgress() {
        val progress = repo.getProgress(mediaId)
        val savedPage = progress?.currentPage ?: 0
        _state.update { it.copy(currentPage = savedPage, initialPage = savedPage) }
    }

    private suspend fun loadPageCount() {
        // If we have extracted pages locally, use that count immediately
        val localCount = _state.value.extractedPages?.size
        if (localCount != null && localCount > 0) {
            _state.update { it.copy(totalPages = localCount) }
        }
        // Always fetch from server to confirm/update (also triggers server-side extraction)
        runCatching { repo.getPageCount(mediaId) }
            .onSuccess { count -> if (count > 0) _state.update { it.copy(totalPages = count) } }
    }

    /** URL for page when streaming from server. */
    fun pageUrl(pageIndex: Int): String = repo.pageUrl(baseUrl, mediaId, pageIndex)

    fun onPageChange(page: Int) {
        val clamped = page.coerceIn(0, (_state.value.totalPages - 1).coerceAtLeast(0))
        _state.update { it.copy(currentPage = clamped) }
        scheduleSync()
    }

    fun seekToPage(page: Int) = _state.update { it.copy(seekToPage = page) }
    fun clearSeek() = _state.update { it.copy(seekToPage = -1) }
    fun toggleControls() = _state.update { it.copy(showControls = !it.showControls) }

    fun toggleDirection() {
        val newRtl = !_state.value.isRtl
        _state.update { it.copy(isRtl = newRtl) }
        viewModelScope.launch { prefs.setRtl(mediaId, newRtl) }
    }

    fun toggleDoublePage() {
        val newVal = !_state.value.doublePage
        _state.update { it.copy(doublePage = newVal) }
        viewModelScope.launch { prefs.setDoublePage(mediaId, newVal) }
    }

    private fun scheduleSync() {
        syncJob?.cancel()
        syncJob = viewModelScope.launch {
            delay(3_000)
            val s = _state.value
            repo.saveProgress(mediaId, s.currentPage, s.currentPage >= s.totalPages - 1)
            repo.syncProgress(mediaId)
        }
    }

    override fun onCleared() {
        super.onCleared()
        val s = _state.value
        viewModelScope.launch {
            repo.saveProgress(mediaId, s.currentPage, s.currentPage >= s.totalPages - 1)
            repo.syncProgress(mediaId)
        }
    }
}
