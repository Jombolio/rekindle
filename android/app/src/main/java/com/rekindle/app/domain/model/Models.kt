package com.rekindle.app.domain.model

import kotlin.math.roundToInt

data class ServerSource(
    val id: String,
    val name: String,
    val baseUrl: String,
    val token: String? = null,
    val permissionLevel: Int = 2,
)

data class Library(
    val id: String,
    val name: String,
    val path: String,
    val type: String = "comic",
)

data class Media(
    val id: String,
    val title: String,
    val sortTitle: String,
    val format: String,
    val mediaType: String,
    val relativePath: String,
    val parentId: String?,
    val pageCount: Int?,
    val libraryId: String,
    // Server-assigned cover cache path; changes when the archive is replaced,
    // used as the Coil disk-cache key to bypass stale entries.
    val coverCachePath: String? = null,
) {
    val displayTitle: String get() = title.ifBlank { sortTitle }
    val isFolder: Boolean get() = mediaType == "folder"
    val isImageBased: Boolean get() = format in listOf("cbz", "cbr", "pdf")
}

data class ReadingProgress(
    val mediaId: String,
    val currentPage: Int,
    val isCompleted: Boolean,
    val lastReadAt: Long,
    /** How far through the current chapter, 0 to 1. Text books only. */
    val positionFraction: Double? = null,
)

/**
 * Per-user reading state for one media item, as shown on its cover. Mirrors
 * the server's `ProgressSummary`.
 *
 * @param progress Fraction read, 0 to 1. For a series, the average over all its chapters.
 * @param newCount Series only: chapters added since the user last read anything in it.
 * @param isNew Chapters only: added since the user last read the series, not opened yet.
 */
data class ProgressSummary(
    val mediaId: String,
    val progress: Float,
    val isCompleted: Boolean,
    val newCount: Int = 0,
    val isNew: Boolean = false,
) {
    /** Whether there is anything to draw: started reading, or finished. */
    val isStarted: Boolean get() = isCompleted || progress > 0f
    val percent: Int get() = (progress * 100).roundToInt()

    companion object {
        /**
         * From this device's local progress, for when the server can't be
         * reached. Only possible for a single archive: a series' progress spans
         * chapters that may never have been opened here. Without a known
         * [pageCount] the fraction can't be computed, so only completion shows.
         */
        fun fromLocal(
            mediaId: String,
            currentPage: Int,
            isCompleted: Boolean,
            pageCount: Int?,
        ): ProgressSummary {
            val fraction = when {
                isCompleted -> 1f
                pageCount != null && pageCount > 0 -> (currentPage.toFloat() / pageCount).coerceIn(0f, 1f)
                else -> 0f
            }
            return ProgressSummary(mediaId, fraction, isCompleted)
        }
    }
}

data class PagedResponse<T>(
    val items: List<T>,
    val total: Int,
    val page: Int,
    val pageSize: Int,
    val totalPages: Int,
)

data class AdminUser(
    val id: String,
    val username: String,
    val permissionLevel: Int,
    val createdAt: String,
) {
    val isAdmin: Boolean get() = permissionLevel >= 4
    val permissionLabel: String get() = when (permissionLevel) {
        1 -> "Read-only"
        2 -> "Download"
        3 -> "Manage Media"
        4 -> "Admin"
        else -> "Level $permissionLevel"
    }
}

data class MangaMetadata(
    val mediaId: String,
    val title: String?,
    val synopsis: String?,
    val genres: String?,
    val score: Double?,
    val status: String?,
    val year: Int?,
    val malId: Int?,
    val anilistId: Int?,
    val comicvineId: Int?,
    val source: String?,
    val lastScrapedAt: String?,
) {
    val genreList: List<String> get() =
        genres?.split(",")?.map { it.trim() }?.filter { it.isNotEmpty() } ?: emptyList()

    fun formatStatus(): String = status
        ?.split("_")
        ?.joinToString(" ") { w -> w.lowercase().replaceFirstChar { it.uppercase() } }
        ?: ""
}

data class MetadataConfig(val malClientIdSet: Boolean, val comicvineApiKeySet: Boolean = false)

enum class ScrapeStatus { CREATED, NO_CHANGE, CONFLICT }

data class ScrapeResult(
    val status: ScrapeStatus,
    val data: MangaMetadata,
    val existing: MangaMetadata? = null,
)

data class AdminStats(
    val userCount: Int,
    val libraryCount: Int,
    val mediaCount: Int,
    val cacheSizeBytes: Long,
) {
    val cacheSizeLabel: String get() {
        val mb = cacheSizeBytes / (1024.0 * 1024.0)
        return if (mb < 1024) "%.1f MB".format(mb)
        else "%.2f GB".format(mb / 1024.0)
    }
}
