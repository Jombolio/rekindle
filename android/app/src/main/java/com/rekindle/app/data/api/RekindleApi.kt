package com.rekindle.app.data.api

import com.rekindle.app.data.model.CreateLibraryRequest
import com.rekindle.app.data.model.LibraryDto
import com.rekindle.app.data.model.LoginRequest
import com.rekindle.app.data.model.LoginResponse
import com.rekindle.app.data.model.SetupRequest
import com.rekindle.app.data.model.MediaDto
import com.rekindle.app.data.model.PageCountDto
import com.rekindle.app.data.model.PagedResponseDto
import com.rekindle.app.data.model.ReadingProgressDto
import com.rekindle.app.data.model.SaveProgressRequest
import com.rekindle.app.data.model.UpdateLibraryRequest
import okhttp3.ResponseBody
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.PUT
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
}
