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

// ── Admin ─────────────────────────────────────────────────────────────────

data class AdminUserDto(
    val id: String,
    val username: String,
    val permissionLevel: Int,
    val createdAt: String,
)

data class AdminStatsDto(
    val userCount: Int,
    val libraryCount: Int,
    val mediaCount: Int,
    val cacheSizeBytes: Long,
)

data class ScanProgressDto(
    val phase: String = "idle",
    val filesTotal: Int = 0,
    val filesProcessed: Int = 0,
    val added: Int = 0,
    val removed: Int = 0,
    val folders: Int = 0,
    val coversQueued: Int = 0,
    val coversGenerated: Int = 0,
)

data class CreateUserRequest(val username: String, val password: String, val permissionLevel: Int = 2)
data class UpdatePermissionRequest(val permissionLevel: Int)
data class UpdatePasswordRequest(val password: String)
data class UploadResponseDto(val message: String, val fileName: String? = null)
data class ClearCacheResponseDto(val message: String, val freedBytes: Long = 0)

fun AdminUserDto.toDomain() = com.rekindle.app.domain.model.AdminUser(id, username, permissionLevel, createdAt)
fun AdminStatsDto.toDomain() = com.rekindle.app.domain.model.AdminStats(userCount, libraryCount, mediaCount, cacheSizeBytes)

// ── Metadata ──────────────────────────────────────────────────────────────

data class MangaMetadataDto(
    val mediaId: String,
    val title: String? = null,
    val synopsis: String? = null,
    val genres: String? = null,
    val score: Double? = null,
    val status: String? = null,
    val year: Int? = null,
    val malId: Int? = null,
    val anilistId: Int? = null,
    val comicvineId: Int? = null,
    val source: String? = null,
    val lastScrapedAt: String? = null,
)

data class MetadataConfigDto(
    val malClientIdSet: Boolean = false,
    val comicvineApiKeySet: Boolean = false,
)
data class SetMetadataConfigRequest(val malClientId: String?, val comicvineApiKey: String? = null)

fun MangaMetadataDto.toDomain() = com.rekindle.app.domain.model.MangaMetadata(
    mediaId, title, synopsis, genres, score, status, year, malId, anilistId, comicvineId, source, lastScrapedAt,
)
fun MetadataConfigDto.toDomain() = com.rekindle.app.domain.model.MetadataConfig(malClientIdSet, comicvineApiKeySet)
