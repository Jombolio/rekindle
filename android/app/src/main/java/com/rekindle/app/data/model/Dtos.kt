package com.rekindle.app.data.model

import com.google.gson.annotations.SerializedName
import com.rekindle.app.domain.model.Library
import com.rekindle.app.domain.model.Media
import com.rekindle.app.domain.model.PagedResponse
import com.rekindle.app.domain.model.ReadingProgress

data class LibraryDto(
    val id: String,
    val name: String,
    @SerializedName("rootPath") val path: String,
    val type: String = "comic",
)

data class MediaDto(
    val id: String,
    val title: String,
    val sortTitle: String? = null,
    val format: String,
    @SerializedName("mediaType") val mediaType: String = "archive",
    @SerializedName("relativePath") val relativePath: String = "",
    @SerializedName("parentId") val parentId: String? = null,
    val pageCount: Int? = null,
    val libraryId: String,
    // Server-assigned cover cache path; changes when the archive is replaced.
    val coverCachePath: String? = null,
)

data class ReadingProgressDto(
    val mediaId: String? = null,
    val currentPage: Int = 0,
    val isCompleted: Boolean = false,
    val lastReadAt: String? = null,
)

data class PagedResponseDto<T>(
    val items: List<T>,
    val total: Int,
    val page: Int,
    val pageSize: Int,
    val totalPages: Int,
)

data class PageCountDto(
    val pageCount: Int,
    val spreads: List<Boolean> = emptyList(),
)

data class LoginRequest(val username: String, val password: String)
data class LoginResponse(val token: String, val permissionLevel: Int = 2)
data class SetupRequest(val username: String, val password: String, val setupToken: String)

data class SaveProgressRequest(val currentPage: Int, val isCompleted: Boolean)

data class CreateLibraryRequest(val name: String, val rootPath: String, val type: String)
data class UpdateLibraryRequest(val name: String, val rootPath: String, val type: String)

// Mappers
fun LibraryDto.toDomain() = Library(id, name, path, type)
fun MediaDto.toDomain() = Media(
    id, title, sortTitle ?: title, format, mediaType, relativePath, parentId, pageCount,
    libraryId, coverCachePath,
)
fun ReadingProgressDto.toDomain() = ReadingProgress(
    mediaId = mediaId ?: "",
    currentPage = currentPage,
    isCompleted = isCompleted,
    lastReadAt = 0L,
)
fun <T, R> PagedResponseDto<T>.toDomain(mapper: (T) -> R) = PagedResponse(
    items = items.map(mapper),
    total = total,
    page = page,
    pageSize = pageSize,
    totalPages = totalPages,
)
