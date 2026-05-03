package com.rekindle.app.domain.model

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
)

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
