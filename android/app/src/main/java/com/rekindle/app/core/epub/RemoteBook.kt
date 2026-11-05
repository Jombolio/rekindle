package com.rekindle.app.core.epub

import com.rekindle.app.data.api.RekindleApi
import java.io.InputStream
import java.net.URLEncoder

/**
 * A book streamed from the server, one file at a time as the WebView asks for it.
 * Nothing is written to disk, so reading works for accounts that aren't allowed to
 * keep a copy. Calls block, which is what the WebView's request thread expects.
 */
class RemoteBook(
    private val api: RekindleApi,
    private val mediaId: String,
    override val title: String,
    override val chapters: List<EpubChapter>,
) : ReaderBook {

    override fun open(path: String): InputStream? = runCatching {
        val response = api.getBookContent(mediaId, encodePath(path)).execute()
        if (response.isSuccessful) response.body()?.byteStream() else null
    }.getOrNull()

    override fun close() = Unit

    private fun encodePath(path: String) = path.split('/').joinToString("/") {
        // URLEncoder is for forms, where a space is '+'; in a path it must be %20.
        URLEncoder.encode(it, "UTF-8").replace("+", "%20")
    }
}
