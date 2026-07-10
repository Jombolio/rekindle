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

    // Bounds concurrent page extraction (PDF rasterisation / full-archive image buffering) so a
    // large folder download doesn't run many memory-heavy extractions at once and OOM.
    private val extractionSemaphore = Semaphore(2)

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
            // Don't clobber a download that started while the DB read was in flight.
            _states.update { map -> if (map.containsKey(mediaId)) map else map + (mediaId to restored) }
        }
    }

    /**
     * Like [stateFor] but restores from disk (DB) first when the state isn't in memory yet,
     * so a caller (e.g. the EPUB reader opened offline from Downloads) doesn't race the
     * fire-and-forget [restoreIfNeeded] and wrongly conclude the item isn't downloaded.
     */
    suspend fun awaitState(mediaId: String): DownloadState {
        _states.value[mediaId]?.let { return it }
        val restored = downloadManager.restore(mediaId)
        // Don't clobber a download that started while the DB read was in flight.
        _states.update { map -> if (map.containsKey(mediaId)) map else map + (mediaId to restored) }
        return _states.value[mediaId] ?: restored
    }

    /**
     * Atomically claims [mediaId] for a new transfer by marking it DOWNLOADING,
     * unless one is already in flight. Both the individual and the folder path
     * claim through here, so they can never write the same file concurrently.
     */
    private fun claimDownload(mediaId: String): Boolean {
        var claimed = false
        _states.update { map ->
            val status = map[mediaId]?.status
            if (status == DownloadStatus.DOWNLOADING || status == DownloadStatus.EXTRACTING) {
                claimed = false
                map
            } else {
                claimed = true
                map + (mediaId to DownloadState(status = DownloadStatus.DOWNLOADING))
            }
        }
        return claimed
    }

    fun download(mediaId: String, format: String, title: String, relativePath: String) {
        // Claiming also immediately reflects the queued state, so the button blocks
        // duplicate taps and shows feedback while waiting for a semaphore slot.
        if (!claimDownload(mediaId)) return

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
                    extractionSemaphore.withPermit {
                        runCatching { downloadManager.extractPages(mediaId, localPath, format) {} }
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
            // Re-derive from the DB: if the transfer had already finished, blanking
            // the state would show a completed download as not downloaded.
            val restored = downloadManager.restore(mediaId)
            update(mediaId, restored)
        }
    }

    fun delete(mediaId: String) {
        scope.launch {
            downloadManager.delete(mediaId)
            update(mediaId, DownloadState())
        }
    }

    /** Purges every download from the device (files + DB) and clears in-memory state. */
    fun purgeAll() {
        scope.launch {
            downloadManager.deleteAll()
            _states.value = emptyMap()
            _folderStates.value = emptyMap()
        }
    }

    fun extractedPages(mediaId: String): List<String>? =
        downloadManager.loadExtractedPages(mediaId)

    /** All completed downloads as a cold Flow — backs the offline Downloads screen. */
    fun completedDownloads() = downloadManager.observeCompletedDownloads()

    /** Local cover path for a downloaded item, or null if not cached. */
    fun localCoverPath(mediaId: String): String? = downloadManager.localCoverPath(mediaId)

    /** Backfills a missing local cover from the server; true if one now exists. */
    suspend fun ensureCover(mediaId: String, baseUrl: String, authHeader: String): Boolean =
        downloadManager.ensureCoverDownloaded(mediaId, baseUrl, authHeader)

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

        val successfulIds = ConcurrentHashMap.newKeySet<String>()
        val claimedIds = ConcurrentHashMap.newKeySet<String>()

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

            val completedCount = AtomicInteger(0)

            // Pre-submit all downloads; semaphore enforces the 3-concurrent cap.
            coroutineScope {
                toDownload.forEach { archive ->
                    launch {
                        semaphore.withPermit {
                            if (!coroutineContext.isActive) return@withPermit
                            // Claim through the shared guard so an individual download of
                            // the same archive can't open a second writer on the file.
                            if (!claimDownload(archive.id)) return@withPermit
                            claimedIds.add(archive.id)
                            runCatching {
                                downloadManager.download(
                                    mediaId = archive.id,
                                    format = archive.format,
                                    title = archive.displayTitle,
                                    relativePath = archive.relativePath,
                                    serverBaseUrl = baseUrl,
                                    authHeader = "Bearer $token",
                                    onProgress = { update(archive.id, it) },
                                    safBaseUri = safUri,
                                )
                            }.onSuccess { path ->
                                successfulIds.add(archive.id)
                                // Update individual chapter tile immediately (restore once, outside the CAS lambda).
                                val restored = downloadManager.restore(archive.id)
                                _states.update { it + (archive.id to restored) }
                                // Extraction is CPU/memory-bound — fire async (gated) so the next download starts.
                                launch {
                                    extractionSemaphore.withPermit {
                                        runCatching { downloadManager.extractPages(archive.id, path, archive.format) {} }
                                    }
                                }
                            }.onFailure { e ->
                                // Swallowing cancellation here would keep the loop
                                // counting up after the folder download was cancelled.
                                if (e is kotlinx.coroutines.CancellationException) throw e
                                update(archive.id, DownloadState(status = DownloadStatus.FAILED, error = e.message))
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
            // Report what actually happened — claiming "complete" after partial
            // failures hides missing chapters until the user is offline.
            _folderStates.update {
                it + (folderId to if (allDone.size >= grandTotal) {
                    FolderDownloadState(
                        status = FolderDownloadStatus.COMPLETE,
                        total = grandTotal,
                        completed = grandTotal,
                    )
                } else {
                    FolderDownloadState(
                        status = FolderDownloadStatus.FAILED,
                        total = grandTotal,
                        completed = allDone.size,
                        error = "${grandTotal - allDone.size} of $grandTotal chapters failed to download",
                    )
                })
            }

            for ((fId, ids) in folderArchiveIds) {
                if (ids.all { it in allDone }) {
                    downloadManager.saveFolderComplete(fId, ids.size, ids.size)
                }
            }
        }

        _folderJobs[folderId] = job
        job.invokeOnCompletion { cause ->
            _folderJobs.remove(folderId)
            if (cause is kotlinx.coroutines.CancellationException) {
                // Items that were mid-transfer had their DB rows cleaned by the
                // manager; reset their tiles too or they show DOWNLOADING forever.
                val inFlight = claimedIds - successfulIds
                _states.update { map -> map + inFlight.associateWith { DownloadState() } }
            }
        }
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
