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
