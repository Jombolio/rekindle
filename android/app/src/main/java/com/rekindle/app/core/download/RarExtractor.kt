package com.rekindle.app.core.download

/**
 * Bridge to the native libarchive-backed RAR/CBR extractor (`librekindle_rar.so`).
 *
 * libarchive decodes both RAR4 and RAR5 with a clean-room, BSD-2-licensed reader
 * (it does NOT use the license-encumbered unRAR source), which is why it is safe
 * for F-Droid distribution.
 *
 * The native side extracts every image entry to `outDir` and returns an
 * **interleaved** array `[entryPath0, fileName0, entryPath1, fileName1, …]` so the
 * caller can order pages by their original archive path. Returns `null` when the
 * native library is unavailable (e.g. a build without the NDK component) or the
 * archive cannot be opened, in which case callers fall back to server streaming.
 */
object RarExtractor {

    /** True when `librekindle_rar.so` loaded successfully for this ABI. */
    val isAvailable: Boolean = runCatching { System.loadLibrary("rekindle_rar") }.isSuccess

    /**
     * Extracts image entries of the CBR/RAR at [archivePath] (a plain filesystem
     * path — content:// URIs must be copied to a temp file by the caller first)
     * into [outDir]. Returns the interleaved [entryPath, fileName, …] array, or
     * `null` if extraction was not possible.
     */
    fun extract(archivePath: String, outDir: String): Array<String>? =
        if (isAvailable) runCatching { nativeExtract(archivePath, outDir) }.getOrNull() else null

    private external fun nativeExtract(archivePath: String, outDir: String): Array<String>?
}
