package com.rekindle.app.data.api

import com.rekindle.app.data.model.AdminStatsDto
import com.rekindle.app.data.model.MangaMetadataDto
import com.rekindle.app.data.model.MetadataConfigDto
import com.rekindle.app.data.model.SetMetadataConfigRequest
import com.rekindle.app.data.model.AdminUserDto
import com.rekindle.app.data.model.ClearCacheResponseDto
import com.rekindle.app.data.model.CreateLibraryRequest
import com.rekindle.app.data.model.CreateUserRequest
import com.rekindle.app.data.model.LibraryDto
import com.rekindle.app.data.model.LoginRequest
import com.rekindle.app.data.model.LoginResponse
import com.rekindle.app.data.model.MediaDto
import com.rekindle.app.data.model.PageCountDto
import com.rekindle.app.data.model.PagedResponseDto
import com.rekindle.app.data.model.ReadingProgressDto
import com.rekindle.app.data.model.SaveProgressRequest
import com.rekindle.app.data.model.ScanProgressDto
import com.rekindle.app.data.model.SetupRequest
import com.rekindle.app.data.model.UpdateLibraryRequest
import com.rekindle.app.data.model.UpdatePasswordRequest
import com.rekindle.app.data.model.UpdatePermissionRequest
import com.rekindle.app.data.model.UploadResponseDto
import okhttp3.MultipartBody
import okhttp3.RequestBody
import okhttp3.ResponseBody
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.Multipart
import retrofit2.http.POST
import retrofit2.http.PUT
import retrofit2.http.Part
import retrofit2.http.Path
import retrofit2.http.Query
import retrofit2.http.Streaming

interface RekindleApi {

    @POST("api/auth/login")
    suspend fun login(@Body request: LoginRequest): LoginResponse

    @POST("api/auth/setup")
    suspend fun setup(@Body request: SetupRequest): LoginResponse

    @GET("api/auth/setup/status")
    suspend fun setupStatus(): Map<String, Boolean>

    @GET("api/libraries")
    suspend fun getLibraries(): List<LibraryDto>

    @GET("api/libraries/{id}")
    suspend fun getLibraryById(@Path("id") id: String): LibraryDto

    @POST("api/libraries")
    suspend fun createLibrary(@Body request: CreateLibraryRequest): LibraryDto

    @PUT("api/libraries/{id}")
    suspend fun updateLibrary(
        @Path("id") id: String,
        @Body request: UpdateLibraryRequest,
    ): LibraryDto

    @DELETE("api/libraries/{id}")
    suspend fun deleteLibrary(@Path("id") id: String)

    @GET("api/media")
    suspend fun getMedia(
        @Query("libraryId") libraryId: String,
        @Query("page") page: Int = 1,
        @Query("pageSize") pageSize: Int = 50,
    ): PagedResponseDto<MediaDto>

    @GET("api/media/{id}")
    suspend fun getMediaById(@Path("id") id: String): MediaDto

    @GET("api/media/{id}/chapters")
    suspend fun getChapters(@Path("id") folderId: String): List<MediaDto>

    @GET("api/media/{id}/pagecount")
    suspend fun getPageCount(@Path("id") id: String): PageCountDto

    @GET("api/media/{id}/progress")
    suspend fun getProgress(@Path("id") id: String): ReadingProgressDto

    @POST("api/media/{id}/progress")
    suspend fun saveProgress(
        @Path("id") id: String,
        @Body request: SaveProgressRequest,
    ): ReadingProgressDto

    @GET("api/media/{id}/page/{pageNum}")
    @Streaming
    suspend fun getPage(
        @Path("id") id: String,
        @Path("pageNum") pageNum: Int,
    ): ResponseBody

    @POST("api/libraries/{id}/scan")
    suspend fun scanLibrary(@Path("id") libraryId: String)

    // ── Users (admin) ────────────────────────────────────────────────────────
    @GET("api/users")
    suspend fun getUsers(): List<AdminUserDto>

    @POST("api/users")
    suspend fun createUser(@Body request: CreateUserRequest): AdminUserDto

    @PUT("api/users/{id}/permission")
    suspend fun updateUserPermission(
        @Path("id") userId: String,
        @Body request: UpdatePermissionRequest,
    )

    @PUT("api/users/{id}/password")
    suspend fun updateUserPassword(
        @Path("id") userId: String,
        @Body request: UpdatePasswordRequest,
    )

    @DELETE("api/users/{id}")
    suspend fun deleteUser(@Path("id") userId: String)

    // ── Admin stats & cache ───────────────────────────────────────────────────
    @GET("api/admin/stats")
    suspend fun getAdminStats(): AdminStatsDto

    @DELETE("api/admin/cache")
    suspend fun clearCache(): ClearCacheResponseDto

    // ── Admin upload ──────────────────────────────────────────────────────────
    @Multipart
    @POST("api/admin/upload")
    suspend fun uploadArchive(
        @Part("libraryId") libraryId: RequestBody,
        @Part("relativePath") relativePath: RequestBody?,
        @Part file: MultipartBody.Part,
    ): UploadResponseDto

    // ── Folder search ─────────────────────────────────────────────────────────
    @GET("api/media/search")
    suspend fun searchFolders(
        @Query("libraryId") libraryId: String,
        @Query("q") query: String,
    ): List<MediaDto>

    // ── Scan progress ─────────────────────────────────────────────────────────
    @GET("api/libraries/{id}/scan/progress")
    suspend fun getScanProgress(@Path("id") libraryId: String): ScanProgressDto

    // ── Manga metadata ────────────────────────────────────────────────────────
    @GET("api/metadata/{mediaId}")
    suspend fun getMetadata(@Path("mediaId") mediaId: String): MangaMetadataDto

    @POST("api/metadata/{mediaId}/scrape")
    suspend fun scrapeMetadata(@Path("mediaId") mediaId: String): MangaMetadataDto

    @GET("api/admin/metadata/config")
    suspend fun getMetadataConfig(): MetadataConfigDto

    @PUT("api/admin/metadata/config")
    suspend fun setMetadataConfig(@Body request: SetMetadataConfigRequest)
}
