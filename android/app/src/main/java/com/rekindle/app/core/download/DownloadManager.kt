package com.rekindle.app.core.download

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.ParcelFileDescriptor
import androidx.documentfile.provider.DocumentFile
import com.rekindle.app.data.db.DownloadDao
import com.rekindle.app.data.db.DownloadEntity
import com.rekindle.app.data.db.FolderDownloadDao
import com.rekindle.app.data.db.FolderDownloadEntity
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
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
        // Cache the cover locally so it renders offline (best-effort — never fails the download).
        runCatching { downloadCover(mediaId, serverBaseUrl, authHeader) }
        onProgress(DownloadState(status = DownloadStatus.COMPLETE, progress = 1f, localPath = localPath))
        localPath
    }

    /**
     * Extracts [localPath] into per-page image files under the media's cache dir
     * plus a `manifest.txt` listing them, so the reader can render pages locally
     * with no server. Decoding is format-aware:
     *   - cbz / zip → unzip image entries as-is
     *   - pdf       → rasterise each page with the platform [PdfRenderer]
     *   - cbr / rar → not yet supported (needs a RAR5 decoder); pages stream from
     *                 the server until that lands.
     * A manifest is only written when extraction actually produced pages, so an
     * unsupported archive is retried by a future capable build rather than being
     * cached as "extracted but empty".
     */
    suspend fun extractPages(
        mediaId: String,
        localPath: String,
        format: String,
        onProgress: (DownloadState) -> Unit,
    ): String = withContext(Dispatchers.IO) {
        onProgress(DownloadState(status = DownloadStatus.EXTRACTING, progress = 1f, localPath = localPath))

        val dir = extractedDir(mediaId)
        dir.mkdirs()
        val manifest = File(dir, "manifest.txt")
        if (manifest.exists()) return@withContext dir.absolutePath

        val pageNames = when (format.lowercase()) {
            "pdf" -> extractPdfPages(localPath, dir)
            // libarchive (RAR4+RAR5); fall back to a zip attempt for the occasional
            // .cbr that is really a mislabelled ZIP.
            "cbr", "rar" -> extractRarPages(localPath, dir)
                .ifEmpty { runCatching { extractZipPages(localPath, dir) }.getOrDefault(emptyList()) }
            else -> extractZipPages(localPath, dir) // cbz / zip
        }

        // Only persist a manifest once extraction produced pages, so an unsupported
        // format isn't cached as an empty (permanent) result.
        if (pageNames.isNotEmpty()) {
            manifest.writeText(pageNames.joinToString("\n"))
        }
        dir.absolutePath
    }

    /** Unzips image entries from a CBZ/ZIP archive into [dir] as zero-padded page files. */
    private fun extractZipPages(localPath: String, dir: File): List<String> {
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
        return entries.mapIndexed { i, (name, bytes) ->
            val ext = name.substringAfterLast('.', "jpg").lowercase()
            val pageName = "${i.toString().padStart(5, '0')}.$ext"
            File(dir, pageName).writeBytes(bytes)
            pageName
        }
    }

    /**
     * Rasterises every page of a PDF to a JPEG in [dir] using the platform
     * [PdfRenderer] (API 21+). Pages render onto a white background at
     * [PDF_TARGET_LONG_SIDE]px on the long edge. Encrypted PDFs throw here and
     * are handled by the caller's runCatching (pages then stream from the server).
     */
    private fun extractPdfPages(localPath: String, dir: File): List<String> {
        val names = mutableListOf<String>()
        openSeekableFd(localPath).use { pfd ->
            PdfRenderer(pfd).use { renderer ->
                for (i in 0 until renderer.pageCount) {
                    renderer.openPage(i).use { page ->
                        val scale = (PDF_TARGET_LONG_SIDE.toFloat() /
                            maxOf(page.width, page.height).coerceAtLeast(1)).coerceAtMost(PDF_MAX_SCALE)
                        val w = (page.width * scale).toInt().coerceAtLeast(1)
                        val h = (page.height * scale).toInt().coerceAtLeast(1)
                        val bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
                        try {
                            Canvas(bitmap).drawColor(Color.WHITE) // flatten transparency
                            page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                            val pageName = "${i.toString().padStart(5, '0')}.jpg"
                            File(dir, pageName).outputStream().use { out ->
                                bitmap.compress(Bitmap.CompressFormat.JPEG, 90, out)
                            }
                            names += pageName
                        } finally {
                            bitmap.recycle() // free native pixels even if render/compress throws
                        }
                    }
                }
            }
        }
        return names
    }

    /**
     * Extracts image entries from a CBR/RAR archive via the native libarchive
     * bridge ([RarExtractor]). Pages are ordered by their original archive path
     * to match the CBZ path's sort. Returns an empty list when the native library
     * is unavailable or the archive can't be read (caller then streams from server).
     */
    private fun extractRarPages(localPath: String, dir: File): List<String> {
        // libarchive needs a real file path; copy content:// (SAF) sources to a temp file.
        val (archiveFile, isTemp) = ensureLocalArchive(localPath)
        try {
            val flat = RarExtractor.extract(archiveFile.absolutePath, dir.absolutePath)
                ?: return emptyList()
            return flat.toList().chunked(2)
                .filter { it.size == 2 }
                .sortedBy { it[0] }   // order by original entry path
                .map { it[1] }        // written file name
        } finally {
            if (isTemp) archiveFile.delete()
        }
    }

    /** Returns a real [File] for [localPath], copying content:// URIs to a temp file
     *  (second value is true when a temp copy was made and should be deleted). */
    private fun ensureLocalArchive(localPath: String): Pair<File, Boolean> =
        if (localPath.startsWith("content://")) {
            val tmp = File.createTempFile("rekindle-rar", ".bin", context.cacheDir)
            try {
                openInputStream(localPath).use { input -> tmp.outputStream().use { input.copyTo(it) } }
            } catch (e: Exception) {
                tmp.delete() // don't orphan the temp copy if the SAF read/copy fails
                throw e
            }
            tmp to true
        } else {
            File(localPath) to false
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
        File(coversDir(), "$mediaId.jpg").delete()
        downloadDao.delete(mediaId)
    }

    /** A cold [Flow] of all completed downloads, for the offline Downloads screen. */
    fun observeCompletedDownloads(): Flow<List<DownloadEntity>> = downloadDao.observeCompleted()

    /** Absolute path of the locally-cached cover for [mediaId], or null if absent. */
    fun localCoverPath(mediaId: String): String? =
        File(coversDir(), "$mediaId.jpg").takeIf { it.exists() }?.absolutePath

    /**
     * Backfills a missing cover from the server so it's available offline. No-op if the
     * cover is already cached. Returns true when a cover is present afterwards. Best-effort
     * — network failures are swallowed (the item just keeps its placeholder/URL fallback).
     */
    suspend fun ensureCoverDownloaded(mediaId: String, serverBaseUrl: String, authHeader: String): Boolean =
        withContext(Dispatchers.IO) {
            if (localCoverPath(mediaId) != null) return@withContext false
            runCatching { downloadCover(mediaId, serverBaseUrl, authHeader) }
            localCoverPath(mediaId) != null
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

    /** A seekable read-only descriptor for [path] (file or content URI) — required by [PdfRenderer]. */
    private fun openSeekableFd(path: String): ParcelFileDescriptor =
        if (path.startsWith("content://")) {
            context.contentResolver.openFileDescriptor(Uri.parse(path), "r")
                ?: error("Cannot open file descriptor: $path")
        } else {
            ParcelFileDescriptor.open(File(path), ParcelFileDescriptor.MODE_READ_ONLY)
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

    // Persistent (NOT cache) so decoded pages survive OS cache eviction / "Clear cache" and
    // stay readable offline; removed by delete(). Mirrors the archive's external-files location,
    // falling back to internal storage when external is unavailable.
    private fun extractedDir(mediaId: String): File {
        val base = context.getExternalFilesDir(null) ?: context.filesDir
        return File(base, "rekindle/extracted/$mediaId")
    }

    /** Persistent (non-cache) directory for downloaded cover thumbnails. */
    private fun coversDir(): File = File(context.filesDir, "rekindle/covers")

    /** Fetches the media cover to coversDir/{mediaId}.jpg. Best-effort; caller wraps in runCatching. */
    private fun downloadCover(mediaId: String, serverBaseUrl: String, authHeader: String) {
        val dir = coversDir().apply { mkdirs() }
        val url = "${serverBaseUrl.trimEnd('/')}/api/media/$mediaId/cover"
        val request = Request.Builder().url(url).header("Authorization", authHeader).build()
        okHttpClient.newCall(request).execute().use { response ->
            if (!response.isSuccessful) return
            val body = response.body ?: return
            // Write to a temp file and atomically swap in on success, so an interrupted
            // transfer never leaves a truncated cover that would render blank forever.
            val target = File(dir, "$mediaId.jpg")
            val tmp = File(dir, "$mediaId.jpg.tmp")
            try {
                tmp.outputStream().use { out -> body.byteStream().use { it.copyTo(out) } }
                if (!tmp.renameTo(target)) {
                    tmp.copyTo(target, overwrite = true)
                    tmp.delete()
                }
            } catch (e: Exception) {
                tmp.delete()
                throw e
            }
        }
    }

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

    private companion object {
        /** Long-edge target resolution (px) for rasterised PDF pages. */
        const val PDF_TARGET_LONG_SIDE = 1600
        /** Never upscale a PDF page beyond this factor of its native size. */
        const val PDF_MAX_SCALE = 3f
    }
}

