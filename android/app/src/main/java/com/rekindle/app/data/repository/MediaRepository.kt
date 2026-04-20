package com.rekindle.app.data.repository

import com.rekindle.app.data.api.RekindleApi
import com.rekindle.app.data.db.ProgressQueueDao
import com.rekindle.app.data.db.ProgressQueueEntity
import com.rekindle.app.data.model.SaveProgressRequest
import com.rekindle.app.data.model.toDomain
import com.rekindle.app.domain.model.Media
import com.rekindle.app.domain.model.PagedResponse
import com.rekindle.app.domain.model.ReadingProgress
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class MediaRepository @Inject constructor(
    private val api: RekindleApi,
    private val progressDao: ProgressQueueDao,
) {
    suspend fun getMedia(libraryId: String, page: Int = 1, pageSize: Int = 50): PagedResponse<Media> =
        api.getMedia(libraryId, page, pageSize).toDomain { it.toDomain() }

    suspend fun getMediaById(id: String): Media =
        api.getMediaById(id).toDomain()

    suspend fun getChapters(folderId: String): List<Media> =
        api.getChapters(folderId).map { it.toDomain() }

    suspend fun getPageCount(mediaId: String): Int =
        api.getPageCount(mediaId).pageCount

    suspend fun getProgress(mediaId: String): ReadingProgress? = try {
        api.getProgress(mediaId).toDomain()
    } catch (_: Exception) {
        null
    }

    suspend fun saveProgress(mediaId: String, currentPage: Int, isCompleted: Boolean) {
        progressDao.upsert(
            ProgressQueueEntity(
                mediaId = mediaId,
                currentPage = currentPage,
                isCompleted = isCompleted,
                lastReadAt = System.currentTimeMillis(),
                synced = false,
            )
        )
    }

    suspend fun syncProgress(mediaId: String) {
        val local = progressDao.getByMediaId(mediaId) ?: return
        try {
            api.saveProgress(mediaId, SaveProgressRequest(local.currentPage, local.isCompleted))
            progressDao.markSynced(mediaId)
        } catch (_: Exception) { /* retry later */ }
    }

    suspend fun syncAllPending() {
        progressDao.getUnsynced().forEach { syncProgress(it.mediaId) }
    }

    fun pageUrl(baseUrl: String, mediaId: String, pageNum: Int): String =
        "${baseUrl.trimEnd('/')}/api/media/$mediaId/page/$pageNum"

    fun coverUrl(baseUrl: String, mediaId: String): String =
        "${baseUrl.trimEnd('/')}/api/media/$mediaId/cover"
}
