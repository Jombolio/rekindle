package com.rekindle.app.ui.viewmodel

import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.rekindle.app.data.repository.DownloadRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import javax.inject.Inject

data class DownloadItem(
    val mediaId: String,
    val title: String,
    val format: String,
    val coverPath: String?,
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
    /** First available local cover among the chapters, used as the folder thumbnail. */
    val coverPath: String? get() = items.firstNotNullOfOrNull { it.coverPath }
}

/**
 * Backs the offline Downloads screen. Reads the local `downloads` table directly
 * (no server call) and groups chapters into series folders so downloads are
 * browsable and openable with no network.
 */
@HiltViewModel
class DownloadsViewModel @Inject constructor(
    private val downloadRepo: DownloadRepository,
) : ViewModel() {

    /** Downloads grouped into series folders (derived from each item's storage path). */
    val folders: StateFlow<List<DownloadFolder>> = downloadRepo.completedDownloads()
        .map { list ->
            list.map {
                DownloadItem(
                    mediaId = it.mediaId,
                    title = it.title,
                    format = it.format,
                    coverPath = downloadRepo.localCoverPath(it.mediaId),
                    series = seriesOf(it.localPath),
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
