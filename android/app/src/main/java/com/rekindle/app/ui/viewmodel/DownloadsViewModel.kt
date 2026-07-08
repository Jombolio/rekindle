package com.rekindle.app.ui.viewmodel

import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.rekindle.app.core.prefs.PrefsStore
import com.rekindle.app.data.repository.DownloadRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

data class DownloadItem(
    val mediaId: String,
    val title: String,
    val format: String,
    /** Locally-downloaded cover (shows offline); null for items downloaded before covers were cached. */
    val coverPath: String?,
    /** Server cover endpoint, loaded via Coil when there is no local cover. */
    val coverUrl: String?,
    val series: String,
) {
    val isImageBased: Boolean get() = format.lowercase() in listOf("cbz", "cbr", "pdf")
}

/** A series folder grouping the downloaded chapters that share a parent directory. */
data class DownloadFolder(
    val series: String,
    val items: List<DownloadItem>,
) {
    val count: Int get() = items.size
    /** First available local cover among the chapters (offline thumbnail). */
    val coverPath: String? get() = items.firstNotNullOfOrNull { it.coverPath }
    /** Server cover of a representative chapter, used when no local cover exists. */
    val coverUrl: String? get() = items.firstOrNull { it.coverUrl != null }?.coverUrl
}

/**
 * Backs the offline Downloads screen. Reads the local `downloads` table directly
 * (no server call) and groups chapters into series folders. Covers prefer the
 * locally-downloaded file and otherwise load from the server cover endpoint via Coil.
 */
@HiltViewModel
class DownloadsViewModel @Inject constructor(
    private val downloadRepo: DownloadRepository,
    private val prefs: PrefsStore,
) : ViewModel() {

    /** Bearer header for loading server covers of downloaded items (active source). */
    val authHeader: StateFlow<String> = prefs.token
        .map { "Bearer ${it ?: ""}" }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), "")

    // Bumped after covers are backfilled so the folder list re-maps and picks up the
    // now-local cover files (making them available offline, not just Coil-cached).
    private val coverRefresh = MutableStateFlow(0)

    init {
        // Backfill covers for downloads made before covers were cached locally.
        viewModelScope.launch { backfillCovers() }
    }

    /** Downloads grouped into series folders (derived from each item's storage path). */
    val folders: StateFlow<List<DownloadFolder>> =
        combine(downloadRepo.completedDownloads(), prefs.serverUrl, coverRefresh) { list, baseUrl, _ ->
            val base = baseUrl.trimEnd('/')
            list.map { e ->
                DownloadItem(
                    mediaId = e.mediaId,
                    title = e.title,
                    format = e.format,
                    coverPath = downloadRepo.localCoverPath(e.mediaId),
                    coverUrl = if (base.isBlank()) null else "$base/api/media/${e.mediaId}/cover",
                    series = seriesOf(e.localPath),
                )
            }
                .groupBy { it.series }
                .map { (series, items) ->
                    DownloadFolder(series, items.sortedWith(compareBy(NaturalComparator) { it.title }))
                }
                .sortedWith(compareBy(NaturalComparator) { it.series })
        }
            // localCoverPath / path parsing do blocking work — keep the mapping off the main thread.
            .flowOn(Dispatchers.IO)
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    fun delete(mediaId: String) = downloadRepo.delete(mediaId)

    /** Deletes every download from this device (files + DB). */
    fun purgeAll() = downloadRepo.purgeAll()

    /**
     * Best-effort: downloads any missing covers from the server (active source) so they
     * persist locally for offline use. Runs once per screen open; a no-op for items whose
     * cover is already cached. Requires a reachable server, so it silently does nothing offline.
     */
    private suspend fun backfillCovers() {
        val base = prefs.serverUrl.first().trimEnd('/')
        val token = prefs.token.first()
        if (base.isBlank() || token.isNullOrBlank()) return
        val auth = "Bearer $token"
        var changed = false
        for (entity in downloadRepo.completedDownloads().first()) {
            if (downloadRepo.localCoverPath(entity.mediaId) == null &&
                downloadRepo.ensureCover(entity.mediaId, base, auth)
            ) {
                changed = true
            }
        }
        if (changed) coverRefresh.value++
    }

    /**
     * Derives the series (parent folder) from a download's stored path. Downloads mirror
     * the server's layout (e.g. ".../Absolute Batman/Chapter_1.cbz"), so the file's
     * immediate parent directory is the series. Handles filesystem paths and SAF
     * content:// URIs; falls back to [DEFAULT_FOLDER] when there is no parent folder.
     */
    private fun seriesOf(localPath: String?): String {
        if (localPath.isNullOrBlank()) return DEFAULT_FOLDER
        val decoded = if (localPath.startsWith("content://")) {
            Uri.parse(localPath).lastPathSegment ?: localPath
        } else {
            localPath
        }
        val parts = decoded.replace('\\', '/').trimEnd('/').split('/').filter { it.isNotBlank() }
        val parent = parts.getOrNull(parts.size - 2)
        // Guard against storage-root prefixes (e.g. "primary:Download", the download base dir).
        return parent?.takeIf { it.isNotBlank() && !it.contains(':') && it != DOWNLOAD_BASE_DIR }
            ?: DEFAULT_FOLDER
    }

    private companion object {
        const val DEFAULT_FOLDER = "Downloads"
        const val DOWNLOAD_BASE_DIR = "Rekindle Downloads"
    }
}

/** Compares strings with embedded numbers in natural order ("Chapter 2" before "Chapter 10"). */
object NaturalComparator : Comparator<String> {
    private val chunk = Regex("""\d+|\D+""")
    override fun compare(a: String, b: String): Int {
        val ac = chunk.findAll(a).map { it.value }.toList()
        val bc = chunk.findAll(b).map { it.value }.toList()
        for (i in 0 until minOf(ac.size, bc.size)) {
            val x = ac[i]
            val y = bc[i]
            val cmp = if (x[0].isDigit() && y[0].isDigit()) {
                (x.toLongOrNull() ?: Long.MAX_VALUE).compareTo(y.toLongOrNull() ?: Long.MAX_VALUE)
            } else {
                x.compareTo(y, ignoreCase = true)
            }
            if (cmp != 0) return cmp
        }
        return ac.size - bc.size
    }
}
