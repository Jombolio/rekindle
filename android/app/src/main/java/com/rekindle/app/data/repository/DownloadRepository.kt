package com.rekindle.app.data.repository

import com.rekindle.app.core.download.DownloadManager
import com.rekindle.app.core.download.DownloadState
import com.rekindle.app.core.download.DownloadStatus
import com.rekindle.app.core.prefs.PrefsStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.util.concurrent.ConcurrentHashMap
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class DownloadRepository @Inject constructor(
    private val downloadManager: DownloadManager,
    private val prefs: PrefsStore,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val _states = MutableStateFlow<Map<String, DownloadState>>(emptyMap())
    val states: StateFlow<Map<String, DownloadState>> = _states.asStateFlow()

    private val _jobs = ConcurrentHashMap<String, Job>()

    fun stateFor(mediaId: String): DownloadState =
        _states.value[mediaId] ?: DownloadState()

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

        val job = scope.launch {
            val baseUrl = prefs.serverUrl.first()
            val token = prefs.token.first() ?: ""
            runCatching {
                val localPath = downloadManager.download(
                    mediaId = mediaId,
                    format = format,
                    title = title,
                    relativePath = relativePath,
                    serverBaseUrl = baseUrl,
                    authHeader = "Bearer $token",
                    onProgress = { update(mediaId, it) },
                )
                downloadManager.extractPages(
                    mediaId = mediaId,
                    localPath = localPath,
                    onProgress = { update(mediaId, it) },
                )
                update(mediaId, downloadManager.restore(mediaId))
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

    /** Load extracted page paths for the reader (null if not extracted). */
    fun extractedPages(mediaId: String): List<String>? =
        downloadManager.loadExtractedPages(mediaId)

    private fun update(mediaId: String, state: DownloadState) {
        _states.update { it + (mediaId to state) }
    }
}
