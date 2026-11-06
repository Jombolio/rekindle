package com.rekindle.app.data.repository

import com.rekindle.app.core.epub.EpubChapter
import com.rekindle.app.core.epub.RemoteBook
import com.rekindle.app.data.api.RekindleApi
import com.rekindle.app.data.db.ProgressQueueDao
import com.rekindle.app.data.db.ProgressQueueEntity
import com.rekindle.app.data.model.ProgressSummaryRequest
import com.rekindle.app.data.model.SaveProgressRequest
import com.rekindle.app.data.model.toDomain
import com.rekindle.app.domain.model.Library
import com.rekindle.app.domain.model.Media
import com.rekindle.app.domain.model.PagedResponse
import com.rekindle.app.domain.model.ProgressSummary
import com.rekindle.app.domain.model.ReadingProgress
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
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
            return ReadingProgress(local.mediaId, local.currentPage, local.isCompleted, local.lastReadAt, local.positionFraction)
        }
        return try {
            api.getProgress(mediaId).toDomain()
        } catch (_: Exception) {
            // Offline: fall back to the locally-queued progress so a downloaded item
            // resumes at the saved page (and completed archives restart at 0) with no server.
            local?.let {
                ReadingProgress(it.mediaId, it.currentPage, it.isCompleted, it.lastReadAt, it.positionFraction)
            }
        }
    }

    /** Opens a book for reading from the server, a chapter at a time. */
    suspend fun openRemoteBook(mediaId: String): RemoteBook {
        val manifest = api.getBookManifest(mediaId)
        return RemoteBook(
            api = api,
            mediaId = mediaId,
            title = manifest.title,
            chapters = manifest.chapters.map { EpubChapter(it.title, it.path) },
        )
    }

    suspend fun saveProgress(
        mediaId: String,
        currentPage: Int,
        isCompleted: Boolean,
        positionFraction: Double? = null,
    ) {
        progressDao.upsert(
            ProgressQueueEntity(
                mediaId = mediaId,
                currentPage = currentPage,
                isCompleted = isCompleted,
                lastReadAt = System.currentTimeMillis(),
                synced = false,
                positionFraction = positionFraction,
            )
        )
    }

    private val _coverProgressChanged = MutableSharedFlow<Unit>(
        extraBufferCapacity = 1,
        onBufferOverflow = BufferOverflow.DROP_OLDEST,
    )

    /**
     * Emits when the server has new reading progress that covers should show.
     * Grid and chapter screens stay alive under the reader, so they refetch
     * their [getProgressSummaries] on this rather than on screen resume, which
     * would race the exit-time sync.
     */
    val coverProgressChanged: SharedFlow<Unit> = _coverProgressChanged.asSharedFlow()

    /**
     * Reading state for the covers of [items], keyed by media id. Falls back
     * to this device's own progress (archives only) when the server can't be
     * reached or predates the endpoint.
     */
    /**
     * Marks [mediaId] as read, or removes the mark, and returns what to tell the
     * user. A series is marked chapter by chapter on the server. Reading progress
     * isn't touched.
     */
    suspend fun setReadMark(mediaId: String, marked: Boolean, isSeries: Boolean): String = try {
        val response = if (marked) api.markRead(mediaId) else api.unmarkRead(mediaId)
        when {
            response.isSuccessful -> {
                _coverProgressChanged.tryEmit(Unit)
                when {
                    marked && isSeries -> "Series marked as read."
                    marked -> "Marked as read."
                    isSeries -> "Read marks removed."
                    else -> "Read mark removed."
                }
            }
            response.code() == 404 -> "Your server needs updating to mark chapters as read."
            else -> "Couldn't change the read mark."
        }
    } catch (e: CancellationException) {
        throw e
    } catch (_: Exception) {
        "Couldn't reach the server."
    }

    /**
     * Leaves [mediaId] out of its series' progress, or counts it again, and returns
     * what to tell the user. The archive's own progress isn't touched.
     */
    suspend fun setTrackingIgnored(mediaId: String, ignored: Boolean): String = try {
        val response = if (ignored) api.ignoreTracking(mediaId) else api.trackAgain(mediaId)
        when {
            response.isSuccessful -> {
                _coverProgressChanged.tryEmit(Unit)
                if (ignored) "Left out of the series' progress." else "Counted in the series' progress again."
            }
            response.code() == 404 -> "Your server needs updating for this."
            else -> "Couldn't make the change."
        }
    } catch (e: CancellationException) {
        throw e
    } catch (_: Exception) {
        "Couldn't reach the server."
    }

    suspend fun getProgressSummaries(items: List<Media>): Map<String, ProgressSummary> {
        if (items.isEmpty()) return emptyMap()
        return try {
            items.map { it.id }
                .chunked(MAX_SUMMARY_IDS)
                .flatMap { api.getProgressSummaries(ProgressSummaryRequest(it)) }
                .associate { it.mediaId to it.toDomain() }
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            val archives = items.filter { !it.isFolder }
            val local = archives.map { it.id }
                .chunked(MAX_SUMMARY_IDS)
                .flatMap { progressDao.getByMediaIds(it) }
                .associateBy { it.mediaId }
            archives.mapNotNull { media ->
                local[media.id]?.let {
                    ProgressSummary.fromLocal(media.id, it.currentPage, it.isCompleted, media.pageCount)
                }
            }.associateBy { it.mediaId }
        }
    }

    /**
     * @param notifyCovers emit [coverProgressChanged] once the server has the
     * write. Only exit-time syncs ask for it: the grid can't be seen while
     * reading, and refetching it on every debounced page sync is wasted work.
     */
    suspend fun syncProgress(mediaId: String, notifyCovers: Boolean = false) {
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
                    local.positionFraction,
                ),
            )
            // Only clear the synced flag if the row is still the one we sent — a
            // page turn between the read and here writes a newer unsynced row that
            // must NOT be marked synced, or that progress would never be sent.
            progressDao.markSyncedIfUnchanged(
                mediaId, local.currentPage, local.isCompleted, local.lastReadAt,
            )
            if (notifyCovers) _coverProgressChanged.tryEmit(Unit)
        } catch (_: Exception) { /* retry later */ }
    }

    /** Syncs all queued progress; returns true only if nothing remains unsynced. */
    suspend fun syncAllPending(): Boolean {
        val pending = progressDao.getUnsynced()
        pending.forEach { syncProgress(it.mediaId) }
        if (pending.isNotEmpty()) _coverProgressChanged.tryEmit(Unit)
        return progressDao.getUnsynced().isEmpty()
    }

    suspend fun searchFolders(libraryId: String, query: String): List<Media> =
        api.searchFolders(libraryId, query).map { it.toDomain() }

    fun pageUrl(baseUrl: String, mediaId: String, pageNum: Int): String =
        "${baseUrl.trimEnd('/')}/api/media/$mediaId/page/$pageNum"

    fun coverUrl(baseUrl: String, mediaId: String): String =
        "${baseUrl.trimEnd('/')}/api/media/$mediaId/cover"

    private companion object {
        /** The server's per-request limit; also keeps Room's IN (...) lists small. */
        const val MAX_SUMMARY_IDS = 500
    }
}
