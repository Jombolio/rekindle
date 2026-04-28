package com.rekindle.app.core.download

import android.content.Context
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import com.rekindle.app.data.db.DownloadDao
import com.rekindle.app.data.db.DownloadEntity
import com.rekindle.app.data.db.FolderDownloadDao
import com.rekindle.app.data.db.FolderDownloadEntity
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.util.zip.ZipInputStream
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class DownloadManager @Inject constructor(
    @ApplicationContext private val context: Context,
    private val okHttpClient: OkHttpClient,
    private val downloadDao: DownloadDao,
    private val folderDownloadDao: FolderDownloadDao,
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

    /**
     * Downloads the archive for [mediaId].
     *
     * When [safBaseUri] is provided the file is written into the SAF tree the
     * user selected; otherwise it lands in the app-private external directory.
     * Returns the stored path — either an absolute filesystem path or a
     * `content://` URI string when SAF is active.
     */
    suspend fun download(
        mediaId: String,
        format: String,
        title: String,
        relativePath: String,
        serverBaseUrl: String,
        authHeader: String,
        onProgress: (DownloadState) -> Unit,
        safBaseUri: Uri? = null,
    ): String = withContext(Dispatchers.IO) {
        upsert(mediaId, format, title, DownloadStatus.DOWNLOADING, 0f, null)
        onProgress(DownloadState(status = DownloadStatus.DOWNLOADING))

        // Resolve destination — either a SAF document or a plain File.
        val (localPath, outputStream) = if (safBaseUri != null) {
            val docUri = createSafFile(safBaseUri, mediaId, relativePath, format)
                ?: error("Cannot create file in the selected folder — check storage permission")
            Pair(docUri.toString(), context.contentResolver.openOutputStream(docUri)
                ?: error("Cannot open output stream for selected folder"))
        } else {
            val destFile = appDestinationFile(mediaId, format, relativePath)
            destFile.parentFile?.mkdirs()
            Pair(destFile.absolutePath, destFile.outputStream())
        }

        val url = "${serverBaseUrl.trimEnd('/')}/api/media/$mediaId/download"
        val request = Request.Builder().url(url).header("Authorization", authHeader).build()

        try {
            outputStream.use { out ->
                okHttpClient.newCall(request).execute().use { response ->
                    if (!response.isSuccessful) error("HTTP ${response.code}")
                    val body = response.body ?: error("Empty body")
                    val total = body.contentLength().takeIf { it > 0 }

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
        } catch (e: Exception) {
            // Clean up the partial file on failure.
            deleteByPath(localPath)
            throw e
        }

        upsert(mediaId, format, title, DownloadStatus.COMPLETE, 1f, localPath)
        onProgress(DownloadState(status = DownloadStatus.COMPLETE, progress = 1f, localPath = localPath))
        localPath
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

        // Open the archive from either a content URI or a plain file path.
        val archiveStream: InputStream = openInputStream(localPath)

        val entries = mutableListOf<Pair<String, ByteArray>>()
        ZipInputStream(archiveStream.buffered()).use { zip ->
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
        entity?.localPath?.let { deleteByPath(it) }
        extractedDir(mediaId).deleteRecursively()
        downloadDao.delete(mediaId)
    }

    suspend fun cancelIncomplete(mediaId: String) = withContext(Dispatchers.IO) {
        val entity = downloadDao.getByMediaId(mediaId) ?: return@withContext
        if (entity.status != DownloadStatus.COMPLETE.name) {
            entity.localPath?.let { deleteByPath(it) }
            downloadDao.delete(mediaId)
        }
    }

    // ── Folder-level persistence ──────────────────────────────────────────────

    suspend fun completedMediaIds(mediaIds: Set<String>): Set<String> =
        withContext(Dispatchers.IO) {
            val allComplete = downloadDao.getAllCompleteMediaIds().toSet()
            allComplete.intersect(mediaIds)
        }

    suspend fun restoreFolder(folderId: String): FolderDownloadState? =
        withContext(Dispatchers.IO) {
            val entity = folderDownloadDao.getByFolderId(folderId) ?: return@withContext null
            val status = runCatching { FolderDownloadStatus.valueOf(entity.status) }
                .getOrDefault(FolderDownloadStatus.IDLE)
            FolderDownloadState(status = status, total = entity.total, completed = entity.completed)
        }

    suspend fun saveFolderComplete(folderId: String, total: Int, completed: Int) =
        withContext(Dispatchers.IO) {
            folderDownloadDao.upsert(
                FolderDownloadEntity(folderId, FolderDownloadStatus.COMPLETE.name, total, completed)
            )
        }

    // ── Private helpers ───────────────────────────────────────────────────────

    /**
     * Creates (or replaces) a file in the SAF tree rooted at [baseUri],
     * mirroring the [relativePath] directory structure.
     * [mediaId] is used as the filename fallback when [relativePath] is blank.
     */
    private fun createSafFile(baseUri: Uri, mediaId: String, relativePath: String, format: String): Uri? {
        var dir = DocumentFile.fromTreeUri(context, baseUri) ?: return null
        val mimeType = mimeTypeFor(format)

        if (relativePath.isNotBlank()) {
            val parts = relativePath.replace('\\', '/').split('/')
            // Traverse / create subdirectories for everything except the final filename.
            for (i in 0 until parts.size - 1) {
                dir = dir.findFile(parts[i])
                    ?: dir.createDirectory(parts[i])
                    ?: return null
            }
            val filename = parts.last()
            dir.findFile(filename)?.delete() // remove stale partial download
            return dir.createFile(mimeType, filename)?.uri
        } else {
            val filename = "$mediaId.$format"
            dir.findFile(filename)?.delete()
            return dir.createFile(mimeType, filename)?.uri
        }
    }

    private fun openInputStream(path: String): InputStream =
        if (path.startsWith("content://")) {
            context.contentResolver.openInputStream(Uri.parse(path))
                ?: error("Cannot open content URI: $path")
        } else {
            File(path).inputStream()
        }

    private fun deleteByPath(path: String) {
        if (path.startsWith("content://")) {
            runCatching { android.provider.DocumentsContract.deleteDocument(context.contentResolver, Uri.parse(path)) }
        } else {
            File(path).delete()
        }
    }

    private fun appDestinationFile(mediaId: String, format: String, relativePath: String): File {
        val base = context.getExternalFilesDir(null)?.let { File(it, "Rekindle Downloads") }
            ?: File(context.filesDir, "Rekindle Downloads")
        return if (relativePath.isNotBlank()) File(base, relativePath)
        else File(base, "$mediaId.$format")
    }

    private fun extractedDir(mediaId: String): File =
        File(context.cacheDir, "rekindle/extracted/$mediaId")

    private fun mimeTypeFor(format: String): String = when (format.lowercase()) {
        "cbz", "zip" -> "application/zip"
        "cbr", "rar" -> "application/x-rar-compressed"
        "pdf"        -> "application/pdf"
        "epub"       -> "application/epub+zip"
        else         -> "application/octet-stream"
    }

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

