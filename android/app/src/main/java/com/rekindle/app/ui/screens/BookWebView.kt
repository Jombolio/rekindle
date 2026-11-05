package com.rekindle.app.ui.screens

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.view.GestureDetector
import android.view.MotionEvent
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import com.rekindle.app.core.epub.EpubParser
import com.rekindle.app.core.epub.ReaderBook
import java.io.ByteArrayInputStream

/**
 * Shows one chapter of a book at a time. Chapters and their images and stylesheets
 * are served from inside the EPUB under a private host, so relative links resolve
 * as the book's author intended. Nothing else loads: JavaScript stays off and every
 * other request is refused, so opening a book can't reach the network.
 */
@SuppressLint("ViewConstructor", "SetJavaScriptEnabled", "ClickableViewAccessibility")
class BookWebView(
    context: Context,
    private val onTap: () -> Unit,
    private val onLinkToChapter: (Int) -> Unit,
    private val onPositionChanged: (Float) -> Unit,
) : WebView(context) {

    var book: ReaderBook? = null
    var themeCss: String = ""

    /** Which chapter + theme is loaded, to tell a real change from a recomposition. */
    private var loadedKey: String? = null
    private var loadedChapter: String? = null

    private var pendingFraction: Float? = null
    private var restoreDeadline = 0L

    private val restoreTick = object : Runnable {
        override fun run() {
            val target = pendingFraction ?: return
            val now = System.currentTimeMillis()
            if (now > restoreDeadline) {
                pendingFraction = null
                // Too short to scroll: that's the whole chapter read, and without
                // this a book ending in a short afterword could never be finished.
                if (maxScroll() <= 0) onPositionChanged(1f)
                return
            }
            scrollTo(0, (target * maxScroll()).toInt())
            postDelayed(this, RESTORE_TICK_MS)
        }
    }

    init {
        settings.javaScriptEnabled = false
        settings.allowFileAccess = false
        settings.allowContentAccess = false
        webViewClient = BookClient()

        // The WebView consumes touches, so a parent's clickable never fires over the
        // page. Toggle the HUD from a detector while letting the WebView keep handling
        // scrolling and links (returning false). Any touch also ends a pending restore:
        // the reader has taken over.
        val detector = GestureDetector(context, object : GestureDetector.SimpleOnGestureListener() {
            override fun onSingleTapUp(e: MotionEvent): Boolean {
                onTap()
                return false
            }
        })
        setOnTouchListener { v, ev ->
            detector.onTouchEvent(ev)
            if (ev.actionMasked == MotionEvent.ACTION_DOWN) pendingFraction = null
            if (ev.actionMasked == MotionEvent.ACTION_UP) v.performClick()
            false
        }
    }

    /**
     * Shows [chapterPath]. A theme change reloads the page too, since the theme is
     * part of it; that keeps the current spot, and only a new chapter uses [startFraction].
     */
    fun show(chapterPath: String, themeKey: String, startFraction: Float) {
        val key = "$chapterPath|$themeKey"
        if (key == loadedKey) return
        val fraction = if (chapterPath == loadedChapter) currentFraction() else startFraction
        loadedKey = key
        loadedChapter = chapterPath
        loadUrl("https://$BOOK_HOST/${Uri.encode(chapterPath, "/")}")
        restore(fraction)
    }

    /** Applies the reader's font size, keeping the current spot as the text reflows. */
    fun applyFontSize(sizeSp: Float) {
        val zoom = (sizeSp / DEFAULT_FONT_SIZE * 100).toInt()
        if (settings.textZoom == zoom) return
        val fraction = currentFraction()
        settings.textZoom = zoom
        if (loadedKey != null) restore(fraction)
    }

    /** The chapter's height changes as it lays out and its images load, so the target
     *  is held and re-applied until the reader touches the page or it has settled. */
    private fun restore(fraction: Float) {
        removeCallbacks(restoreTick)
        pendingFraction = fraction
        restoreDeadline = System.currentTimeMillis() + RESTORE_WINDOW_MS
        postDelayed(restoreTick, RESTORE_TICK_MS)
    }

    private fun maxScroll(): Int = computeVerticalScrollRange() - computeVerticalScrollExtent()

    private fun currentFraction(): Float {
        pendingFraction?.let { return it }
        val max = maxScroll()
        return if (max <= 0) 0f else (scrollY.toFloat() / max).coerceIn(0f, 1f)
    }

    override fun onScrollChanged(l: Int, t: Int, oldl: Int, oldt: Int) {
        super.onScrollChanged(l, t, oldl, oldt)
        if (pendingFraction == null) onPositionChanged(currentFraction())
    }

    override fun onDetachedFromWindow() {
        removeCallbacks(restoreTick)
        super.onDetachedFromWindow()
    }

    private inner class BookClient : WebViewClient() {
        override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse {
            val uri = request.url
            val book = book
            if (uri.host != BOOK_HOST || book == null) return refused()
            val path = uri.path?.removePrefix("/") ?: return refused()

            // Served as HTML rather than XHTML: one stray character in strict XML
            // would replace the whole chapter with a parse error.
            if (book.chapterIndexOf(path) != null) {
                // When streaming, a dropped connection shouldn't look like a blank page.
                val bytes = runCatching { book.read(path) }.getOrNull()
                    ?: CHAPTER_FAILED.toByteArray()
                val html = EpubParser.renderChapter(EpubParser.decodeText(bytes), themeCss)
                return WebResourceResponse("text/html", "utf-8", ByteArrayInputStream(html.toByteArray()))
            }
            val stream = runCatching { book.open(path) }.getOrNull() ?: return refused()
            return WebResourceResponse(mimeTypeOf(path), null, stream)
        }

        override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
            val uri = request.url
            if (uri.host != BOOK_HOST) {
                if (uri.scheme == "http" || uri.scheme == "https") {
                    runCatching {
                        context.startActivity(
                            Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                        )
                    }
                }
                return true
            }
            val path = uri.path?.removePrefix("/").orEmpty()
            val target = book?.chapterIndexOf(path) ?: return true
            // A link within the current chapter is left to the WebView.
            if (path.equals(loadedChapter, ignoreCase = true)) return false
            onLinkToChapter(target)
            return true
        }

        private fun refused() = WebResourceResponse("text/plain", "utf-8", 404, "Not Found", emptyMap(), ByteArrayInputStream(ByteArray(0)))

        private fun mimeTypeOf(path: String) = when (path.substringAfterLast('.').lowercase()) {
            "css" -> "text/css"
            "png" -> "image/png"
            "jpg", "jpeg" -> "image/jpeg"
            "gif" -> "image/gif"
            "webp" -> "image/webp"
            "svg" -> "image/svg+xml"
            "ttf" -> "font/ttf"
            "otf" -> "font/otf"
            "woff" -> "font/woff"
            "woff2" -> "font/woff2"
            else -> "application/octet-stream"
        }
    }

    private companion object {
        // .invalid can never resolve, so nothing here can leave the device even if
        // a request were ever to get past the interceptor.
        const val CHAPTER_FAILED =
            "<html><body><p>This chapter couldn't be loaded. Check your connection, then " +
                "go to another chapter and back to try again.</p></body></html>"
        const val BOOK_HOST = "book.rekindle.invalid"
        const val DEFAULT_FONT_SIZE = 16f
        const val RESTORE_WINDOW_MS = 2000L
        const val RESTORE_TICK_MS = 100L
    }
}
