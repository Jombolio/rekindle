package com.rekindle.app.core.download

import android.content.Context
import com.rekindle.app.data.db.DownloadDao
import com.rekindle.app.data.db.DownloadEntity
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.util.zip.ZipInputStream
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class DownloadManager @Inject constructor(
    @ApplicationContext private val context: Context,
    private val okHttpClient: OkHttpClient,
    private val downloadDao: DownloadDao,
) {
    private val imageExtensions = setOf("jpg", "jpeg", "png", "webp", "gif", "bmp")

    suspend fun restore(mediaId: String): DownloadState = withContext(Dispatchers.IO) {
        val entity = downloadDao.getByMediaId(mediaId)
            ?: return@withContext DownloadState()

        val status = runCatching { DownloadStatus.valueOf(entity.status) }
            .getOrDefault(DownloadStatus.IDLE)

        if (status == DownloadStatus.COMPLETE && entity.localPath != null) {
            val extractDir = extractedDir(mediaId)
            val manifest = File(extractDir, "manifest.txt")
            DownloadState(
                status = DownloadStatus.COMPLETE,
                progress = 1f,
                localPath = entity.localPath,
                extractedDir = if (manifest.exists()) extractDir.absolutePath else null,
            )
        } else {
            DownloadState(status = status)
        }
    }

    suspend fun download(
        mediaId: String,
        format: String,
        title: String,
        relativePath: String,
        serverBaseUrl: String,
        authHeader: String,
        onProgress: (DownloadState) -> Unit,
    ): String = withContext(Dispatchers.IO) {
        val destFile = destinationFile(mediaId, format, relativePath)
        destFile.parentFile?.mkdirs()

        upsert(mediaId, format, title, DownloadStatus.DOWNLOADING, 0f, null)
        onProgress(DownloadState(status = DownloadStatus.DOWNLOADING))

        val url = "${serverBaseUrl.trimEnd('/')}/api/media/$mediaId/download"
        val request = Request.Builder().url(url).header("Authorization", authHeader).build()

        okHttpClient.newCall(request).execute().use { response ->
            if (!response.isSuccessful) error("HTTP ${response.code}")
            val body = response.body ?: error("Empty body")
            val total = body.contentLength().takeIf { it > 0 }

            destFile.outputStream().use { out ->
                var downloaded = 0L
                val buf = ByteArray(8192)
                body.byteStream().use { input ->
                    var n: Int
                    while (input.read(buf).also { n = it } != -1) {
                        out.write(buf, 0, n)
                        downloaded += n
                        total?.let {
                            onProgress(
                                DownloadState(
                                    status = DownloadStatus.DOWNLOADING,
                                    progress = downloaded.toFloat() / it,
                                )
                            )
                        }
                    }
                }
            }
        }

        upsert(mediaId, format, title, DownloadStatus.COMPLETE, 1f, destFile.absolutePath)
        onProgress(DownloadState(status = DownloadStatus.COMPLETE, progress = 1f, localPath = destFile.absolutePath))
        destFile.absolutePath
    }

    suspend fun extractPages(
        mediaId: String,
        localPath: String,
        onProgress: (DownloadState) -> Unit,
    ): String = withContext(Dispatchers.IO) {
        onProgress(DownloadState(status = DownloadStatus.EXTRACTING, progress = 1f, localPath = localPath))

        val dir = extractedDir(mediaId)
        dir.mkdirs()
        val manifest = File(dir, "manifest.txt")

        if (manifest.exists()) return@withContext dir.absolutePath

        val entries = mutableListOf<Pair<String, ByteArray>>()
        ZipInputStream(File(localPath).inputStream().buffered()).use { zip ->
            var entry = zip.nextEntry
            while (entry != null) {
                val ext = entry.name.substringAfterLast('.', "").lowercase()
                if (!entry.isDirectory && ext in imageExtensions) {
                    entries += entry.name to zip.readBytes()
                }
                zip.closeEntry()
                entry = zip.nextEntry
            }
        }

        entries.sortBy { it.first }
        val pageNames = entries.mapIndexed { i, (name, bytes) ->
            val ext = name.substringAfterLast('.', "jpg").lowercase()
            val pageName = "${i.toString().padStart(5, '0')}.$ext"
            File(dir, pageName).writeBytes(bytes)
            pageName
        }

        manifest.writeText(pageNames.joinToString("\n"))
        dir.absolutePath
    }

    fun loadExtractedPages(mediaId: String): List<String>? {
        val dir = extractedDir(mediaId)
        val manifest = File(dir, "manifest.txt")
        if (!manifest.exists()) return null
        return manifest.readLines()
            .filter { it.isNotBlank() }
            .map { File(dir, it).absolutePath }
    }

    suspend fun delete(mediaId: String) = withContext(Dispatchers.IO) {
        val entity = downloadDao.getByMediaId(mediaId)
        entity?.localPath?.let { File(it).delete() }
        extractedDir(mediaId).deleteRecursively()
        downloadDao.delete(mediaId)
    }

    /** Cleans up an incomplete (cancelled) download without touching extracted pages. */
    suspend fun cancelIncomplete(mediaId: String) = withContext(Dispatchers.IO) {
        val entity = downloadDao.getByMediaId(mediaId) ?: return@withContext
        if (entity.status != DownloadStatus.COMPLETE.name) {
            entity.localPath?.let { File(it).delete() }
            downloadDao.delete(mediaId)
        }
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    private fun destinationFile(mediaId: String, format: String, relativePath: String): File {
        val base = context.getExternalFilesDir(null)?.let { File(it, "Downloads") }
            ?: File(context.filesDir, "Downloads")
        return if (relativePath.isNotBlank()) File(base, relativePath)
        else File(base, "$mediaId.$format")
    }

    private fun extractedDir(mediaId: String): File =
        File(context.cacheDir, "rekindle/extracted/$mediaId")

    private suspend fun upsert(
        mediaId: String,
        format: String,
        title: String,
        status: DownloadStatus,
        progress: Float,
        path: String?,
    ) = downloadDao.upsert(
        DownloadEntity(mediaId, status.name, progress, path, format, title)
    )
}
