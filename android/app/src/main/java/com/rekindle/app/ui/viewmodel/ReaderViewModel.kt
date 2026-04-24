package com.rekindle.app.ui.viewmodel

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.rekindle.app.core.prefs.PrefsStore
import com.rekindle.app.data.repository.DownloadRepository
import com.rekindle.app.data.repository.MediaRepository
import com.rekindle.app.domain.model.Media
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
    val scrollMode: Boolean = false,
    val spineGap: Float = 0f,
    val spreads: List<Boolean> = emptyList(),
    val showControls: Boolean = true,
    val seekToPage: Int = -1,
    val extractedPages: List<String>? = null,
    val siblings: List<Media> = emptyList(),
    /** Non-null while the reader should navigate to a different chapter. */
    val navigateToChapterId: String? = null,
    val navigateToChapterInitialPage: Int = -1,
)

@HiltViewModel
class ReaderViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val repo: MediaRepository,
    private val downloadRepo: DownloadRepository,
    private val prefs: PrefsStore,
) : ViewModel() {

    private val mediaId: String = checkNotNull(savedStateHandle["mediaId"])

    /** -1 means no override; use saved server progress. 0 = start of chapter (chapter advance). */
    private val initialPageOverride: Int = savedStateHandle["initialPage"] ?: -1

    private val libraryType: String? = savedStateHandle.get<String>("libraryType")?.ifBlank { null }

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
                    doublePage = prefs.isDoublePage(mediaId).first(),
                    scrollMode = prefs.isScrollMode(mediaId).first(),
                    spineGap = prefs.spineGap.first(),
                )
            }

            loadExtractedPages()
            loadProgress()
            loadDirection()
            loadPageCount()
            loadSiblings()
        }
    }

    private fun loadExtractedPages() {
        val pages = downloadRepo.extractedPages(mediaId)
        if (pages != null) _state.update { it.copy(extractedPages = pages) }
    }

    private suspend fun loadProgress() {
        val progress = repo.getProgress(mediaId)
        val savedPage = when {
            initialPageOverride >= 0 -> initialPageOverride
            else -> progress?.currentPage ?: 0
        }
        _state.update { it.copy(currentPage = savedPage, initialPage = savedPage) }
    }

    private suspend fun loadDirection() {
        val explicit = prefs.isRtlExplicit(mediaId).first()
        if (explicit != null) {
            _state.update { it.copy(isRtl = explicit) }
            return
        }
        // No explicit user pref — infer from library type (manga → RTL).
        // If the caller passed the type through navigation, skip the API calls.
        if (libraryType != null) {
            if (libraryType == "manga") _state.update { it.copy(isRtl = true) }
            return
        }
        runCatching {
            val media = repo.getMediaById(mediaId)
            val library = repo.getLibraryById(media.libraryId)
            if (library.type == "manga") _state.update { it.copy(isRtl = true) }
        }
    }

    private suspend fun loadPageCount() {
        val localCount = _state.value.extractedPages?.size
        if (localCount != null && localCount > 0) {
            _state.update { it.copy(totalPages = localCount) }
        }
        runCatching { repo.getPageCount(mediaId) }
            .onSuccess { layout ->
                if (layout.count > 0) {
                    _state.update { it.copy(totalPages = layout.count, spreads = layout.spreads) }
                }
            }
    }

    private suspend fun loadSiblings() {
        runCatching { repo.getSiblings(mediaId) }
            .onSuccess { siblings -> _state.update { it.copy(siblings = siblings) } }
    }

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

    fun toggleScrollMode() {
        val newVal = !_state.value.scrollMode
        _state.update { it.copy(scrollMode = newVal) }
        viewModelScope.launch { prefs.setScrollMode(mediaId, newVal) }
    }

    fun updateSpineGap(gap: Float) {
        val clamped = gap.coerceIn(0f, 64f)
        _state.update { it.copy(spineGap = clamped) }
        viewModelScope.launch { prefs.setSpineGap(clamped) }
    }

    /** Triggers navigation to an adjacent chapter, carrying the RTL direction forward
     *  unless the target already has an explicit user pref. */
    fun navigateToChapter(targetId: String, initialPage: Int) {
        val currentIsRtl = _state.value.isRtl
        viewModelScope.launch {
            val targetHasExplicit = prefs.isRtlExplicit(targetId).first()
            if (targetHasExplicit == null) {
                prefs.setRtl(targetId, currentIsRtl)
            }
        }
        _state.update { it.copy(navigateToChapterId = targetId, navigateToChapterInitialPage = initialPage) }
    }

    fun clearNavigation() = _state.update { it.copy(navigateToChapterId = null) }

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
