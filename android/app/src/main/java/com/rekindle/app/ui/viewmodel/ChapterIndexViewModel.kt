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
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class ChapterIndexState(
    val chapters: List<Media> = emptyList(),
    val loading: Boolean = true,
    val error: String? = null,
)

@HiltViewModel
class ChapterIndexViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val repo: MediaRepository,
    private val downloadRepo: DownloadRepository,
    private val prefs: PrefsStore,
) : ViewModel() {

    private val folderId: String = checkNotNull(savedStateHandle["folderId"])

    private val _state = MutableStateFlow(ChapterIndexState())
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

    var authHeader: String = ""
        private set
    private var baseUrl: String = ""

    init {
        viewModelScope.launch {
            authHeader = "Bearer ${prefs.token.first() ?: ""}"
            baseUrl = prefs.serverUrl.first()
            runCatching { repo.getChapters(folderId) }
                .onSuccess { chapters ->
                    _state.update { it.copy(chapters = chapters, loading = false) }
                    chapters.forEach { downloadRepo.restoreIfNeeded(it.id) }
                }
                .onFailure { e -> _state.update { it.copy(loading = false, error = e.message) } }
        }
    }

    fun downloadStateFor(mediaId: String): DownloadState = downloadStates.value[mediaId] ?: DownloadState()
    fun download(media: Media) = downloadRepo.download(media.id, media.format, media.displayTitle, media.relativePath)
    fun deleteDownload(mediaId: String) = downloadRepo.delete(mediaId)
    fun coverUrl(mediaId: String) = repo.coverUrl(baseUrl, mediaId)
}
