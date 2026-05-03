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
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class MediaGridState(
    val items: List<Media> = emptyList(),
    val loading: Boolean = true,
    val loadingMore: Boolean = false,
    val hasMore: Boolean = false,
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

    private var currentPage = 1
    private val pageSize = 24

    private val _state = MutableStateFlow(MediaGridState())
    val state = _state.asStateFlow()

    val downloadStates = downloadRepo.states.stateIn(
        viewModelScope,
        SharingStarted.Lazily,
        emptyMap(),
    )

    val folderDownloadStates = downloadRepo.folderStates.stateIn(
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

    private val _searchResults = MutableStateFlow<List<Media>>(emptyList())
    val searchResults: StateFlow<List<Media>> = _searchResults.asStateFlow()

    private val _searchLoading = MutableStateFlow(false)
    val searchLoading: StateFlow<Boolean> = _searchLoading.asStateFlow()

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
            currentPage = 1
            _state.update { it.copy(loading = true, error = null) }
            runCatching { repo.getMedia(libraryId, page = 1, pageSize = pageSize) }
                .onSuccess { page ->
                    _state.update {
                        it.copy(
                            items = page.items,
                            loading = false,
                            hasMore = page.page < page.totalPages,
                        )
                    }
                    page.items.filter { !it.isFolder }.forEach {
                        downloadRepo.restoreIfNeeded(it.id)
                    }
                }
                .onFailure { e -> _state.update { it.copy(loading = false, error = e.message) } }
        }
    }

    fun loadMore() {
        val s = _state.value
        if (!s.hasMore || s.loadingMore || s.loading) return
        viewModelScope.launch {
            _state.update { it.copy(loadingMore = true) }
            val nextPage = currentPage + 1
            runCatching { repo.getMedia(libraryId, page = nextPage, pageSize = pageSize) }
                .onSuccess { page ->
                    currentPage = nextPage
                    _state.update {
                        it.copy(
                            items = it.items + page.items,
                            loadingMore = false,
                            hasMore = page.page < page.totalPages,
                        )
                    }
                    page.items.filter { !it.isFolder }.forEach {
                        downloadRepo.restoreIfNeeded(it.id)
                    }
                }
                .onFailure { _state.update { it.copy(loadingMore = false) } }
        }
    }

    fun refresh() {
        _searchQuery.value = ""
        _searchResults.value = emptyList()
        load()
    }

    fun setSearchQuery(query: String) {
        _searchQuery.value = query
        if (query.isBlank()) {
            _searchResults.value = emptyList()
            return
        }
        viewModelScope.launch {
            _searchLoading.value = true
            runCatching { repo.searchFolders(libraryId, query) }
                .onSuccess { _searchResults.value = it }
                .onFailure { _searchResults.value = emptyList() }
            _searchLoading.value = false
        }
    }

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
