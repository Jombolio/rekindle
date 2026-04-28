package com.rekindle.app.data.repository

import android.net.Uri
import com.rekindle.app.core.download.DownloadManager
import com.rekindle.app.core.download.DownloadState
import com.rekindle.app.core.download.DownloadStatus
import com.rekindle.app.core.download.FolderDownloadState
import com.rekindle.app.core.download.FolderDownloadStatus
import com.rekindle.app.core.prefs.PrefsStore
import com.rekindle.app.domain.model.Media
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.isActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class DownloadRepository @Inject constructor(
    private val downloadManager: DownloadManager,
    private val prefs: PrefsStore,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    // Limits concurrent file transfers across both individual and folder downloads.
    private val semaphore = Semaphore(3)

    private val _states = MutableStateFlow<Map<String, DownloadState>>(emptyMap())
    val states: StateFlow<Map<String, DownloadState>> = _states.asStateFlow()

    private val _folderStates = MutableStateFlow<Map<String, FolderDownloadState>>(emptyMap())
    val folderStates: StateFlow<Map<String, FolderDownloadState>> = _folderStates.asStateFlow()

    private val _jobs = ConcurrentHashMap<String, Job>()
    private val _folderJobs = ConcurrentHashMap<String, Job>()

    // ── Individual downloads ──────────────────────────────────────────────────

    fun stateFor(mediaId: String): DownloadState = _states.value[mediaId] ?: DownloadState()

    fun restoreIfNeeded(mediaId: String) {
        if (_states.value.containsKey(mediaId)) return
        scope.launch {
            val restored = downloadManager.restore(mediaId)
            _states.update { it + (mediaId to restored) }
        }
    }

    fun download(mediaId: String, format: String, title: String, relativePath: String) {
        val current = stateFor(mediaId).status
        if (current == DownloadStatus.DOWNLOADING || current == DownloadStatus.EXTRACTING) return

        // Immediately reflect the queued state so the button blocks duplicate taps
        // and shows feedback even while waiting for a semaphore slot to open.
        update(mediaId, DownloadState(status = DownloadStatus.DOWNLOADING))

        val job = scope.launch {
            val baseUrl = prefs.serverUrl.first()
            val token = prefs.token.first() ?: ""
            val safUri = resolveSafUri()
            runCatching {
                val localPath = semaphore.withPermit {
                    downloadManager.download(
                        mediaId = mediaId,
                        format = format,
                        title = title,
                        relativePath = relativePath,
                        serverBaseUrl = baseUrl,
                        authHeader = "Bearer $token",
                        onProgress = { update(mediaId, it) },
                        safBaseUri = safUri,
                    )
                }
                // State is already COMPLETE (set by download() via onProgress).
                // Fire extraction in the background — no UI block.
                launch {
                    runCatching {
                        downloadManager.extractPages(mediaId, localPath) {}
                    }
                }
            }.onFailure { e ->
                if (e is kotlinx.coroutines.CancellationException) return@onFailure
                update(mediaId, DownloadState(status = DownloadStatus.FAILED, error = e.message))
            }
        }

        _jobs[mediaId] = job
        job.invokeOnCompletion { _jobs.remove(mediaId) }
    }

    fun cancel(mediaId: String) {
        _jobs[mediaId]?.cancel()
        _jobs.remove(mediaId)
        scope.launch {
            downloadManager.cancelIncomplete(mediaId)
            update(mediaId, DownloadState())
        }
    }

    fun delete(mediaId: String) {
        scope.launch {
            downloadManager.delete(mediaId)
            update(mediaId, DownloadState())
        }
    }

    fun extractedPages(mediaId: String): List<String>? =
        downloadManager.loadExtractedPages(mediaId)

    // ── Folder downloads ──────────────────────────────────────────────────────

    fun folderStateFor(folderId: String): FolderDownloadState =
        _folderStates.value[folderId] ?: FolderDownloadState()

    fun restoreFolderIfNeeded(folderId: String) {
        if (_folderStates.value.containsKey(folderId)) return
        scope.launch {
            val saved = downloadManager.restoreFolder(folderId) ?: return@launch
            _folderStates.update { it + (folderId to saved) }
        }
    }

    fun setFolderState(folderId: String, state: FolderDownloadState) {
        _folderStates.update { it + (folderId to state) }
    }

    /**
     * Downloads all archives in [archives] for [folderId], skipping those
     * already complete. Up to 3 transfers run simultaneously via [semaphore].
     * [folderArchiveIds] maps every visited subfolder to its archive IDs for
     * per-subfolder completion persistence.
     */
    fun downloadFolderArchives(
        folderId: String,
        archives: List<Media>,
        folderArchiveIds: Map<String, Set<String>>,
    ) {
        val existing = folderStateFor(folderId).status
        if (existing == FolderDownloadStatus.DOWNLOADING) return

        val job = scope.launch {
            val baseUrl = prefs.serverUrl.first()
            val token = prefs.token.first() ?: ""
            val safUri = resolveSafUri()

            val alreadyDone = downloadManager.completedMediaIds(archives.map { it.id }.toSet())
            val toDownload = archives.filter { it.id !in alreadyDone }

            if (toDownload.isEmpty()) {
                val total = archives.size
                _folderStates.update {
                    it + (folderId to FolderDownloadState(
                        status = FolderDownloadStatus.COMPLETE, total = total, completed = total,
                    ))
                }
                for ((fId, ids) in folderArchiveIds) {
                    downloadManager.saveFolderComplete(fId, ids.size, ids.size)
                }
                return@launch
            }

            _folderStates.update {
                it + (folderId to FolderDownloadState(
                    status = FolderDownloadStatus.DOWNLOADING,
                    total = toDownload.size,
                    completed = 0,
                ))
            }

            val successfulIds = ConcurrentHashMap.newKeySet<String>()
            val completedCount = AtomicInteger(0)

            // Pre-submit all downloads; semaphore enforces the 3-concurrent cap.
            coroutineScope {
                toDownload.forEach { archive ->
                    launch {
                        semaphore.withPermit {
                            if (!coroutineContext.isActive) return@withPermit
                            runCatching {
                                downloadManager.download(
                                    mediaId = archive.id,
                                    format = archive.format,
                                    title = archive.displayTitle,
                                    relativePath = archive.relativePath,
                                    serverBaseUrl = baseUrl,
                                    authHeader = "Bearer $token",
                                    onProgress = {},
                                    safBaseUri = safUri,
                                )
                            }.onSuccess { path ->
                                successfulIds.add(archive.id)
                                // Update individual chapter tile immediately.
                                _states.update { it + (archive.id to downloadManager.restore(archive.id)) }
                                // Extraction is CPU-bound — fire async so next download starts.
                                launch {
                                    runCatching {
                                        downloadManager.extractPages(archive.id, path) {}
                                    }
                                }
                            }
                        }

                        val done = completedCount.incrementAndGet()
                        _folderStates.update { map ->
                            val cur = map[folderId] ?: return@update map
                            if (cur.status != FolderDownloadStatus.DOWNLOADING) return@update map
                            map + (folderId to cur.copy(completed = done))
                        }
                    }
                }
            }

            val grandTotal = archives.size
            val allDone = alreadyDone + successfulIds
            _folderStates.update {
                it + (folderId to FolderDownloadState(
                    status = FolderDownloadStatus.COMPLETE,
                    total = grandTotal,
                    completed = grandTotal,
                ))
            }

            for ((fId, ids) in folderArchiveIds) {
                if (ids.all { it in allDone }) {
                    downloadManager.saveFolderComplete(fId, ids.size, ids.size)
                }
            }
        }

        _folderJobs[folderId] = job
        job.invokeOnCompletion { _folderJobs.remove(folderId) }
    }

    fun cancelFolderDownload(folderId: String) {
        _folderJobs[folderId]?.cancel()
        _folderJobs.remove(folderId)
        _folderStates.update { it + (folderId to FolderDownloadState()) }
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    /** Returns the SAF base URI if the user has selected a custom folder, or null for app-private storage. */
    private suspend fun resolveSafUri(): Uri? {
        val uriString = prefs.downloadSafUri.first()
        return if (uriString.isNotBlank()) Uri.parse(uriString) else null
    }

    private fun update(mediaId: String, state: DownloadState) {
        _states.update { it + (mediaId to state) }
    }
}
