package com.rekindle.app.data.repository

import com.rekindle.app.data.api.RekindleApi
import com.rekindle.app.data.db.ProgressQueueDao
import com.rekindle.app.data.db.ProgressQueueEntity
import com.rekindle.app.data.model.SaveProgressRequest
import com.rekindle.app.data.model.toDomain
import com.rekindle.app.domain.model.Library
import com.rekindle.app.domain.model.Media
import com.rekindle.app.domain.model.PagedResponse
import com.rekindle.app.domain.model.ReadingProgress
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import java.time.Instant
import javax.inject.Inject
import javax.inject.Singleton

data class PageLayout(val count: Int, val spreads: List<Boolean>)

@Singleton
class MediaRepository @Inject constructor(
    private val api: RekindleApi,
    private val progressDao: ProgressQueueDao,
) {
    suspend fun getMedia(libraryId: String, page: Int = 1, pageSize: Int = 50): PagedResponse<Media> =
        api.getMedia(libraryId, page, pageSize).toDomain { it.toDomain() }

    suspend fun getMediaById(id: String): Media =
        api.getMediaById(id).toDomain()

    suspend fun getLibraryById(id: String): Library =
        api.getLibraryById(id).toDomain()

    suspend fun getChapters(folderId: String): List<Media> =
        api.getChapters(folderId).map { it.toDomain() }

    /**
     * Recursively collects all leaf (non-folder) archives under [folderId], descending
     * into subfolders in parallel. Populates [folderArchiveIds] with each visited folder's
     * archive ids so callers can persist per-folder download completion.
     */
    suspend fun collectLeafArchives(
        folderId: String,
        folderArchiveIds: MutableMap<String, Set<String>>,
    ): List<Media> = coroutineScope {
        val items = getChapters(folderId)
        val directArchives = items.filter { !it.isFolder }
        val subResults = items.filter { it.isFolder }
            .map { async { collectLeafArchives(it.id, folderArchiveIds) } }
            .map { it.await() }
            .flatten()
        val all = directArchives + subResults
        folderArchiveIds[folderId] = all.map { it.id }.toSet()
        all
    }

    suspend fun getSiblings(mediaId: String): List<Media> {
        val media = runCatching { api.getMediaById(mediaId) }.getOrNull() ?: return emptyList()
        val parentId = media.parentId ?: return emptyList()
        return runCatching { api.getChapters(parentId).map { it.toDomain() } }
            .getOrDefault(emptyList())
            .filter { !it.isFolder }
    }

    suspend fun getPageCount(mediaId: String): PageLayout {
        val dto = api.getPageCount(mediaId)
        return PageLayout(dto.pageCount, dto.spreads)
    }

    suspend fun getProgress(mediaId: String): ReadingProgress? {
        val local = progressDao.getByMediaId(mediaId)
        // Unsynced local progress is newer than anything the server has (it was
        // never pushed) — prefer it, or an online open would resume at the stale
        // server page and the debounce would then overwrite the real progress.
        if (local != null && !local.synced) {
            return ReadingProgress(local.mediaId, local.currentPage, local.isCompleted, local.lastReadAt)
        }
        return try {
            api.getProgress(mediaId).toDomain()
        } catch (_: Exception) {
            // Offline: fall back to the locally-queued progress so a downloaded item
            // resumes at the saved page (and completed archives restart at 0) with no server.
            local?.let {
                ReadingProgress(it.mediaId, it.currentPage, it.isCompleted, it.lastReadAt)
            }
        }
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
            api.saveProgress(
                mediaId,
                SaveProgressRequest(
                    local.currentPage,
                    local.isCompleted,
                    // The row's write time, not now(): a queued offline write must
                    // carry when it actually happened so the server orders it
                    // correctly against progress from other devices.
                    Instant.ofEpochMilli(local.lastReadAt).toString(),
                ),
            )
            // Only clear the synced flag if the row is still the one we sent — a
            // page turn between the read and here writes a newer unsynced row that
            // must NOT be marked synced, or that progress would never be sent.
            progressDao.markSyncedIfUnchanged(
                mediaId, local.currentPage, local.isCompleted, local.lastReadAt,
            )
        } catch (_: Exception) { /* retry later */ }
    }

    /** Syncs all queued progress; returns true only if nothing remains unsynced. */
    suspend fun syncAllPending(): Boolean {
        progressDao.getUnsynced().forEach { syncProgress(it.mediaId) }
        return progressDao.getUnsynced().isEmpty()
    }

    suspend fun searchFolders(libraryId: String, query: String): List<Media> =
        api.searchFolders(libraryId, query).map { it.toDomain() }

    fun pageUrl(baseUrl: String, mediaId: String, pageNum: Int): String =
        "${baseUrl.trimEnd('/')}/api/media/$mediaId/page/$pageNum"

    fun coverUrl(baseUrl: String, mediaId: String): String =
        "${baseUrl.trimEnd('/')}/api/media/$mediaId/cover"
}
