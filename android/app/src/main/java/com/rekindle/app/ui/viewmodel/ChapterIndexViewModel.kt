package com.rekindle.app.ui.viewmodel

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.rekindle.app.core.download.DownloadState
import com.rekindle.app.core.download.FolderDownloadState
import com.rekindle.app.core.download.FolderDownloadStatus
import com.rekindle.app.core.prefs.PrefsStore
import com.rekindle.app.data.db.ProgressQueueDao
import com.rekindle.app.data.db.ProgressQueueEntity
import com.rekindle.app.data.repository.DownloadRepository
import com.rekindle.app.data.repository.MediaRepository
import com.rekindle.app.data.repository.MetadataRepository
import com.rekindle.app.domain.model.MangaMetadata
import com.rekindle.app.domain.model.Media
import com.rekindle.app.domain.model.ScrapeResult
import com.rekindle.app.domain.model.ScrapeStatus
import org.json.JSONObject
import retrofit2.HttpException
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
    val readProgress: Map<String, ProgressQueueEntity> = emptyMap(),
    val loading: Boolean = true,
    val error: String? = null,
    val metadata: MangaMetadata? = null,
    val metadataLoading: Boolean = false,
    val metadataScraping: Boolean = false,
    val metadataError: String? = null,
    // Non-null while a conflict is awaiting admin resolution
    val metadataConflict: ScrapeResult? = null,
    val metadataNoChange: Boolean = false,
)

@HiltViewModel
class ChapterIndexViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val repo: MediaRepository,
    private val downloadRepo: DownloadRepository,
    private val metadataRepo: MetadataRepository,
    private val progressDao: ProgressQueueDao,
    private val prefs: PrefsStore,
) : ViewModel() {

    private val folderId: String = checkNotNull(savedStateHandle["folderId"])
    val libraryType: String? = savedStateHandle["libraryType"]

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

    val isAdmin = prefs.permissionLevel.map { it >= 4 }.stateIn(
        viewModelScope,
        SharingStarted.Eagerly,
        false,
    )

    val canManageMedia = prefs.permissionLevel.map { it >= 3 }.stateIn(
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
                    val ids = chapters.filter { !it.isFolder }.map { it.id }
                    val progress = progressDao.getByMediaIds(ids)
                        .associateBy { it.mediaId }
                    _state.update { it.copy(chapters = chapters, readProgress = progress, loading = false) }
                    chapters.forEach { downloadRepo.restoreIfNeeded(it.id) }
                    downloadRepo.restoreFolderIfNeeded(folderId)
                }
                .onFailure { e -> _state.update { it.copy(loading = false, error = e.message) } }

            // Load metadata for manga libraries
            if (libraryType == "manga") {
                _state.update { it.copy(metadataLoading = true) }
                val meta = metadataRepo.getMetadata(folderId)
                _state.update { it.copy(metadata = meta, metadataLoading = false) }
            }
        }
    }

    fun scrapeMetadata() {
        if (_state.value.metadataScraping) return
        viewModelScope.launch {
            _state.update { it.copy(metadataScraping = true, metadataError = null, metadataNoChange = false, metadataConflict = null) }
            runCatching { metadataRepo.scrapeMetadata(folderId) }
                .onSuccess { result ->
                    when (result.status) {
                        ScrapeStatus.CREATED ->
                            _state.update { it.copy(metadata = result.data, metadataScraping = false) }
                        ScrapeStatus.NO_CHANGE ->
                            _state.update { it.copy(metadataScraping = false, metadataNoChange = true) }
                        ScrapeStatus.CONFLICT ->
                            _state.update { it.copy(metadataScraping = false, metadataConflict = result) }
                    }
                }
                .onFailure { e -> _state.update { it.copy(metadataScraping = false, metadataError = e.friendlyMessage()) } }
        }
    }

    fun commitMetadata(metadata: MangaMetadata) {
        viewModelScope.launch {
            runCatching { metadataRepo.commitMetadata(folderId, metadata) }
                .onSuccess { saved -> _state.update { it.copy(metadata = saved, metadataConflict = null) } }
                .onFailure { e -> _state.update { it.copy(metadataError = e.message, metadataConflict = null) } }
        }
    }

    fun updateMetadata(metadata: MangaMetadata) {
        viewModelScope.launch {
            runCatching { metadataRepo.updateMetadata(folderId, metadata) }
                .onSuccess { saved -> _state.update { it.copy(metadata = saved) } }
                .onFailure { e -> _state.update { it.copy(metadataError = e.friendlyMessage()) } }
        }
    }

    fun dismissConflict() = _state.update { it.copy(metadataConflict = null) }
    fun dismissNoChange() = _state.update { it.copy(metadataNoChange = false) }
    fun dismissMetadataError() = _state.update { it.copy(metadataError = null) }

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

    private fun Throwable.friendlyMessage(): String {
        if (this is HttpException) {
            val body = runCatching { response()?.errorBody()?.string() }.getOrNull()
            val serverMsg = body?.let { runCatching { JSONObject(it).optString("error") }.getOrNull() }
            if (!serverMsg.isNullOrBlank()) return serverMsg
            return when (code()) {
                422  -> "No API key configured for this library type."
                404  -> "No metadata found for this title."
                else -> "Server error ${code()}."
            }
        }
        return message ?: "Unknown error."
    }

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
