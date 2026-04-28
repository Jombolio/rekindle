package com.rekindle.app.ui.viewmodel

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.rekindle.app.core.download.DownloadState
import com.rekindle.app.core.download.FolderDownloadState
import com.rekindle.app.core.download.FolderDownloadStatus
import com.rekindle.app.core.prefs.PrefsStore
import com.rekindle.app.data.repository.DownloadRepository
import com.rekindle.app.data.repository.MediaRepository
import com.rekindle.app.domain.model.Media
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.util.concurrent.ConcurrentHashMap
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

    val folderDownloadState = downloadRepo.folderStates.map {
        it[folderId] ?: FolderDownloadState()
    }.stateIn(
        viewModelScope,
        SharingStarted.Eagerly,
        FolderDownloadState(),
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
                    downloadRepo.restoreFolderIfNeeded(folderId)
                }
                .onFailure { e -> _state.update { it.copy(loading = false, error = e.message) } }
        }
    }

    fun downloadStateFor(mediaId: String): DownloadState = downloadRepo.stateFor(mediaId)
    fun download(media: Media) = downloadRepo.download(media.id, media.format, media.displayTitle, media.relativePath)
    fun deleteDownload(mediaId: String) = downloadRepo.delete(mediaId)
    fun cancelDownload(mediaId: String) = downloadRepo.cancel(mediaId)
    fun coverUrl(mediaId: String) = repo.coverUrl(baseUrl, mediaId)

    // ── Folder (bulk) download ────────────────────────────────────────────────

    fun downloadFolder() {
        val status = folderDownloadState.value.status
        if (status == FolderDownloadStatus.FETCHING || status == FolderDownloadStatus.DOWNLOADING) return

        viewModelScope.launch {
            downloadRepo.setFolderState(folderId, FolderDownloadState(FolderDownloadStatus.FETCHING))

            val folderArchiveIds = ConcurrentHashMap<String, Set<String>>()
            val archives = runCatching { collectArchives(folderId, folderArchiveIds) }
                .getOrElse { e ->
                    downloadRepo.setFolderState(
                        folderId,
                        FolderDownloadState(FolderDownloadStatus.FAILED, error = e.message),
                    )
                    return@launch
                }

            downloadRepo.downloadFolderArchives(folderId, archives, folderArchiveIds)
        }
    }

    fun cancelFolderDownload() = downloadRepo.cancelFolderDownload(folderId)

    /** Recursively collects all leaf archives in parallel using coroutine async. */
    private suspend fun collectArchives(
        folderId: String,
        folderArchiveIds: ConcurrentHashMap<String, Set<String>>,
    ): List<Media> = coroutineScope {
        val items = repo.getChapters(folderId)
        val subfolders = items.filter { it.isFolder }
        val directArchives = items.filter { !it.isFolder }

        val subResults = subfolders
            .map { sf -> async { collectArchives(sf.id, folderArchiveIds) } }
            .map { it.await() }
            .flatten()

        val all = directArchives + subResults
        folderArchiveIds[folderId] = all.map { it.id }.toSet()
        all
    }
}
