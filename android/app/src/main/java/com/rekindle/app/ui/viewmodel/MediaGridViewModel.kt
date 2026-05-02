package com.rekindle.app.ui.viewmodel

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.rekindle.app.core.download.DownloadState
import com.rekindle.app.core.prefs.PrefsStore
import com.rekindle.app.data.repository.DownloadRepository
import com.rekindle.app.data.repository.MediaRepository
import com.rekindle.app.domain.model.Media
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class MediaGridState(
    val items: List<Media> = emptyList(),
    val loading: Boolean = true,
    val error: String? = null,
)

@HiltViewModel
class MediaGridViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val repo: MediaRepository,
    private val downloadRepo: DownloadRepository,
    private val prefs: PrefsStore,
) : ViewModel() {

    private val libraryId: String = checkNotNull(savedStateHandle["libraryId"])

    private val _state = MutableStateFlow(MediaGridState())
    val state = _state.asStateFlow()

    val downloadStates = downloadRepo.states.stateIn(
        viewModelScope,
        SharingStarted.Lazily,
        emptyMap(),
    )

    val canDownload = prefs.permissionLevel.map { it >= 2 }.stateIn(
        viewModelScope,
        SharingStarted.Eagerly,
        false,
    )

    private val _searchQuery = MutableStateFlow("")
    val searchQuery = _searchQuery.asStateFlow()

    /** Items filtered by the current search query (case-insensitive title match). */
    val filteredItems: StateFlow<List<Media>> = combine(_state, _searchQuery) { s, q ->
        if (q.isBlank()) s.items
        else s.items.filter { it.displayTitle.contains(q, ignoreCase = true) }
    }.stateIn(viewModelScope, SharingStarted.Eagerly, emptyList())

    var authHeader: String = ""
        private set
    private var baseUrl: String = ""

    init {
        viewModelScope.launch {
            authHeader = "Bearer ${prefs.token.first() ?: ""}"
            baseUrl = prefs.serverUrl.first()
            load()
        }
    }

    private fun load() {
        viewModelScope.launch {
            _state.update { it.copy(loading = true, error = null) }
            runCatching { repo.getMedia(libraryId) }
                .onSuccess { page ->
                    _state.update { it.copy(items = page.items, loading = false) }
                    // Restore download state for each non-folder item
                    page.items.filter { !it.isFolder }.forEach {
                        downloadRepo.restoreIfNeeded(it.id)
                    }
                }
                .onFailure { e -> _state.update { it.copy(loading = false, error = e.message) } }
        }
    }

    fun setSearchQuery(query: String) { _searchQuery.value = query }

    fun downloadStateFor(mediaId: String): DownloadState = downloadStates.value[mediaId] ?: DownloadState()

    fun download(media: Media) {
        downloadRepo.download(
            mediaId = media.id,
            format = media.format,
            title = media.displayTitle,
            relativePath = media.relativePath,
        )
    }

    fun deleteDownload(mediaId: String) = downloadRepo.delete(mediaId)
    fun cancelDownload(mediaId: String) = downloadRepo.cancel(mediaId)

    fun coverUrl(mediaId: String) = repo.coverUrl(baseUrl, mediaId)
}
