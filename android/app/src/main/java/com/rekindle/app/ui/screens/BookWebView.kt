package com.rekindle.app.ui.screens

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.ActionMode
import android.view.GestureDetector
import android.view.Menu
import android.view.MenuItem
import android.view.MotionEvent
import android.view.View
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import com.google.gson.Gson
import com.google.gson.JsonParser
import com.rekindle.app.core.epub.EpubParser
import com.rekindle.app.core.epub.ReaderBook
import com.rekindle.app.core.prefs.BUNDLED_FONT_FILES
import com.rekindle.app.core.prefs.BUNDLED_FONT_PATH
import com.rekindle.app.core.prefs.BookLayout
import com.rekindle.app.core.prefs.DEFAULT_PAGE_TURN_MS
import com.rekindle.app.core.prefs.ReadingCss
import com.rekindle.app.core.readaloud.SentenceMarker
import java.io.ByteArrayInputStream
import java.util.concurrent.Executors
import kotlin.math.abs

/** The class on the sentence being read aloud; the reader's theme colours it. */
const val READ_ALOUD_HIGHLIGHT = "rk-reading"

/**
 * Shows a book in one of four layouts:
 *  - [BookLayout.SCROLL]: one chapter, scrolled.
 *  - [BookLayout.CONTINUOUS]: the book as one scroll, chapters added above and below
 *    as the reader nears them.
 *  - [BookLayout.PAGE] and [BookLayout.SPREAD]: one chapter in pages, which are CSS
 *    columns exactly a screen (or half of one) apart, turned by tapping a side of
 *    the page, swiping, or the reader's arrows.
 *
 * Chapters and their images and stylesheets are served from inside the EPUB under a
 * private host, so relative links resolve as the book's author intended, and the
 * bundled reading fonts are served from the app under the same host. Nothing else
 * loads: every other request is refused, so opening a book can't reach the network.
 * JavaScript is on only so the app can measure and move the page and read the
 * selected text; books can't run any (see EpubParser.CONTENT_SECURITY_POLICY).
 */
@SuppressLint("ViewConstructor", "SetJavaScriptEnabled", "ClickableViewAccessibility")
class BookWebView(
    context: Context,
    private val onTap: () -> Unit,
    private val onLinkToChapter: (Int) -> Unit,
    private val onPositionChanged: (Float) -> Unit,
    private val onDefine: (String) -> Unit,
    private val onTouchedPage: () -> Unit,
    /** Paged layouts: the page shown (the left one of a spread), and how many. */
    private val onPage: (page: Int, count: Int, fraction: Float, turned: Boolean) -> Unit,
    /** Continuous layout: the chapter under the reading line, and how far into it. */
    private val onFlowPosition: (chapter: Int, fraction: Float) -> Unit,
    private val onPastEnd: () -> Unit,
    private val onBeforeStart: () -> Unit,
    /** "Read aloud" was picked for selected text: the chapter and sentence it's in. */
    private val onReadAloudFrom: (chapter: Int, sentence: Int) -> Unit,
) : WebView(context) {

    var book: ReaderBook? = null
    var themeCss: String = ""
    var layout: BookLayout = BookLayout.SCROLL
    var animations: Boolean = true

    /** How long one page turn takes, in milliseconds. */
    var turnMs: Int = DEFAULT_PAGE_TURN_MS

    /** The sentence being read aloud, highlighted and kept on screen. */
    private var readingChapter = -1
    private var readingSentence: Int? = null

    /** What is loaded, to tell a real change from a recomposition. */
    private var loadedKey: String? = null
    private var loadedChapter: String? = null
    private var loadedLayout: BookLayout? = null

    private var pendingFraction: Float? = null
    private var restoreDeadline = 0L

    // Paged layouts. Pages are columns; a spread shows two per screen.
    private var page = 0
    private var pageCount = 0
    private val perScreen get() = if (layout == BookLayout.SPREAD) 2 else 1

    // Continuous layout: which chapters the document holds.
    private var flowFirst = 0
    private var flowLast = 0
    private var flowLoading = false
    private var flowTarget = 0
    private val loader = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    private val restoreTick = object : Runnable {
        override fun run() {
            val target = pendingFraction ?: return
            if (System.currentTimeMillis() > restoreDeadline) {
                pendingFraction = null
                if (layout == BookLayout.SCROLL && maxScroll() <= 0) {
                    // Too short to scroll: that's the whole chapter read, and without
                    // this a book ending in a short afterword could never be finished.
                    onPositionChanged(1f)
                }
                return
            }
            when (layout) {
                BookLayout.SCROLL -> scrollTo(0, (target * maxScroll()).toInt())
                BookLayout.PAGE, BookLayout.SPREAD -> measurePages { count ->
                    val last = ((count - 1) / perScreen) * perScreen
                    val wanted = if (target >= 1f) last else (target * count).toInt()
                    showPage(align(wanted.coerceIn(0, last)), count, animate = false, turned = false)
                }
                BookLayout.CONTINUOUS -> evaluateJavascript(
                    "(function(c,f,top){var e=document.querySelector('section[data-chapter=\"'+c+'\"]');" +
                        "if(!e)return;var r=e.getBoundingClientRect();" +
                        "window.scrollTo(0,r.top+scrollY+f*r.height-top);})($flowTarget,$target,${ReadingCss.TOP_INSET})",
                    null,
                )
            }
            postDelayed(this, RESTORE_TICK_MS)
        }
    }

    private val flowCheck = Runnable { checkFlow() }

    init {
        settings.javaScriptEnabled = true
        settings.allowFileAccess = false
        settings.allowContentAccess = false
        isHorizontalScrollBarEnabled = false
        webViewClient = BookClient()

        // The WebView consumes touches, so a parent's clickable never fires over the
        // page. Taps and swipes are read from a detector while the WebView keeps
        // handling scrolling, selection and links (returning false). Any touch also
        // ends a pending restore: the reader has taken over.
        val detector = GestureDetector(context, object : GestureDetector.SimpleOnGestureListener() {
            override fun onSingleTapUp(e: MotionEvent): Boolean {
                if (layout.paged && !onLink()) {
                    when {
                        e.x < width * TURN_ZONE -> { previousPage(); return false }
                        e.x > width * (1 - TURN_ZONE) -> { nextPage(); return false }
                    }
                }
                onTap()
                return false
            }

            override fun onFling(e1: MotionEvent?, e2: MotionEvent, velocityX: Float, velocityY: Float): Boolean {
                if (!layout.paged || abs(velocityX) < abs(velocityY) || abs(velocityX) < FLING_VELOCITY) return false
                if (velocityX < 0) nextPage() else previousPage()
                return true
            }
        })
        setOnTouchListener { v, ev ->
            detector.onTouchEvent(ev)
            if (ev.actionMasked == MotionEvent.ACTION_DOWN) {
                pendingFraction = null
                onTouchedPage()
            }
            if (ev.actionMasked == MotionEvent.ACTION_UP) v.performClick()
            false
        }
    }

    /** Whether the last touch landed on a link, which should follow it, not turn. */
    private fun onLink(): Boolean = hitTestResult.type.let {
        it == HitTestResult.SRC_ANCHOR_TYPE || it == HitTestResult.SRC_IMAGE_ANCHOR_TYPE
    }

    /**
     * Shows chapter [chapterIndex]. A change of theme or layout reloads the page too,
     * keeping the current spot; only a new chapter uses [startFraction].
     */
    fun show(chapterIndex: Int, styleKey: String, startFraction: Float) {
        val book = book ?: return
        val chapterPath = book.chapters[chapterIndex].path
        val flow = layout == BookLayout.CONTINUOUS
        // In the continuous layout the document starts at a chapter and grows; the
        // chapter being read changes without reloading it.
        val key = if (flow) "flow|$chapterIndex|$styleKey" else "$chapterPath|$styleKey"
        if (key == loadedKey) return
        // The same chapter in the same layout keeps the spot on screen. Anything
        // else uses the position the reader passes in, since this view's own
        // measure of it belongs to what was loaded before.
        val sameView = !flow && chapterPath == loadedChapter && layout == loadedLayout
        val fraction = if (sameView) currentFraction() else startFraction
        loadedKey = key
        loadedChapter = chapterPath
        loadedLayout = layout
        page = 0
        pageCount = 0
        if (flow) {
            flowFirst = chapterIndex
            flowLast = chapterIndex
            flowTarget = chapterIndex
            flowLoading = false
            loadUrl("https://$BOOK_HOST/$FLOW_PATH$chapterIndex")
        } else {
            loadUrl("https://$BOOK_HOST/${Uri.encode(chapterPath, "/")}")
        }
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

    /** The chapter's size changes as it lays out and its images load, so the target
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
        return when (layout) {
            BookLayout.SCROLL -> {
                val max = maxScroll()
                if (max <= 0) 0f else (scrollY.toFloat() / max).coerceIn(0f, 1f)
            }
            BookLayout.PAGE, BookLayout.SPREAD -> if (pageCount <= 0) 0f else page.toFloat() / pageCount
            BookLayout.CONTINUOUS -> lastFlowFraction
        }
    }

    override fun onScrollChanged(l: Int, t: Int, oldl: Int, oldt: Int) {
        super.onScrollChanged(l, t, oldl, oldt)
        when (layout) {
            BookLayout.SCROLL -> if (pendingFraction == null) onPositionChanged(currentFraction())
            BookLayout.CONTINUOUS -> {
                removeCallbacks(flowCheck)
                postDelayed(flowCheck, FLOW_CHECK_MS)
            }
            BookLayout.PAGE, BookLayout.SPREAD -> {}
        }
    }

    // ── Pages ────────────────────────────────────────────────────────────────

    private fun align(page: Int) = page - page % perScreen

    /** Counts the chapter's pages: columns of the laid-out document. */
    private fun measurePages(then: (Int) -> Unit) {
        val share = if (layout == BookLayout.SPREAD) 0.5 else 1.0
        evaluateJavascript(
            "Math.max(1,Math.round(document.documentElement.scrollWidth/(innerWidth*$share)))",
        ) { result -> result?.toIntOrNull()?.let(then) }
    }

    private fun showPage(target: Int, count: Int, animate: Boolean, turned: Boolean) {
        val changed = target != page || count != pageCount
        page = target
        pageCount = count
        // Scrolled by hand rather than with behavior:'smooth', which has no say
        // over how long it takes: a turn has to last as long as the reader's
        // page turn setting, the same one the comic reader and the desktop
        // client use. A duration of 0 jumps. Each turn takes a ticket and
        // stops as soon as a newer one starts, so two turns never fight.
        val ms = if (animate && animations) turnMs.coerceAtLeast(0) else 0
        evaluateJavascript(
            "(function(x,d){var w=window;w.__rkTurn=(w.__rkTurn||0)+1;var id=w.__rkTurn;" +
                "var s=w.scrollX,c=x-s;if(!c)return;" +
                "if(d<=0){w.scrollTo(x,0);return}var t0=null;" +
                "function f(t){if(w.__rkTurn!==id)return;t0=t0||t;" +
                "var p=Math.min(1,(t-t0)/d);" +
                // easeInOutCubic, near enough the clients' easeInOut.
                "var e=p<0.5?4*p*p*p:1-Math.pow(-2*p+2,3)/2;" +
                "w.scrollTo(s+c*e,0);if(p<1)requestAnimationFrame(f)}" +
                "requestAnimationFrame(f)})(${target / perScreen}*innerWidth,$ms)",
            null,
        )
        if (changed || turned) {
            val fraction = if (target + perScreen >= count) 1f else target.toFloat() / count
            // A spread's first column is the blank left page that puts the chapter's
            // opening on the right, so book pages are one behind columns: -1 there.
            if (layout == BookLayout.SPREAD) onPage(target - 1, count - 1, fraction, turned)
            else onPage(target, count, fraction, turned)
        }
    }

    /** Turns to the next page, or past the chapter's end. */
    fun nextPage() {
        pendingFraction = null
        measurePages { count ->
            if (page + perScreen < count) showPage(page + perScreen, count, animate = true, turned = true)
            else onPastEnd()
        }
    }

    /** Turns back a page, or back past the chapter's start. */
    fun previousPage() {
        pendingFraction = null
        measurePages { count ->
            if (page > 0) showPage(maxOf(0, page - perScreen), count, animate = true, turned = true)
            else onBeforeStart()
        }
    }

    // ── Continuous ───────────────────────────────────────────────────────────

    private var lastFlowFraction = 0f

    /** Finds the chapter under the reading line, and adds chapters as the reader nears an end. */
    private fun checkFlow() {
        val book = book ?: return
        evaluateJavascript(
            "(function(top){var y=scrollY+top,s=document.querySelectorAll('section[data-chapter]'),c=-1,f=0;" +
                "for(var i=0;i<s.length;i++){var r=s[i].getBoundingClientRect(),t=r.top+scrollY;" +
                "if(t<=y&&t+r.height>y){c=+s[i].dataset.chapter;f=(y-t)/r.height;break;}}" +
                "var h=document.documentElement.scrollHeight;" +
                "return [c,f,scrollY<innerHeight*1.5?1:0,scrollY+innerHeight>h-innerHeight*1.5?1:0," +
                "scrollY+innerHeight>=h-2?1:0].join(',');})(${ReadingCss.TOP_INSET})",
        ) { raw ->
            val parts = raw?.trim('"')?.split(',') ?: return@evaluateJavascript
            if (parts.size < 5) return@evaluateJavascript
            val chapter = parts[0].toIntOrNull() ?: return@evaluateJavascript
            val nearTop = parts[2] == "1"
            val nearBottom = parts[3] == "1"
            val atEnd = parts[4] == "1"
            if (pendingFraction == null && chapter >= 0) {
                // The bottom of the book counts as the end of its last chapter.
                val fraction = if (atEnd && flowLast == book.chapters.size - 1) 1f
                else parts[1].toFloatOrNull() ?: 0f
                val reported = if (atEnd && flowLast == book.chapters.size - 1) book.chapters.size - 1 else chapter
                lastFlowFraction = fraction
                onFlowPosition(reported, fraction)
            }
            if (nearBottom && flowLast < book.chapters.size - 1) addFlowChapter(flowLast + 1, after = true)
            else if (nearTop && flowFirst > 0) addFlowChapter(flowFirst - 1, after = false)
        }
    }

    private fun addFlowChapter(index: Int, after: Boolean) {
        if (flowLoading) return
        val book = book ?: return
        val key = loadedKey
        flowLoading = true
        loader.execute {
            val path = book.chapters[index].path
            val raw = runCatching { book.read(path) }.getOrNull()
            val section = raw?.let {
                EpubParser.flowSection(index, path, EpubParser.decodeText(it), BOOK_HOST, markSentences = true)
            }
            main.post {
                flowLoading = false
                // The reader may have moved on to another layout or chapter meanwhile.
                if (section == null || key != loadedKey) return@post
                // As a JavaScript string literal.
                val html = Gson().toJson(section)
                if (after) {
                    flowLast = index
                    evaluateJavascript("document.body.insertAdjacentHTML('beforeend',$html)", null)
                } else {
                    flowFirst = index
                    // Keeps the text being read where it is as the chapter goes in above.
                    evaluateJavascript(
                        "(function(h){var d=document.documentElement,before=d.scrollHeight,y=scrollY;" +
                            "document.body.insertAdjacentHTML('afterbegin',h);" +
                            "window.scrollTo(0,y+d.scrollHeight-before);})($html)",
                        null,
                    )
                }
                postDelayed(flowCheck, FLOW_CHECK_MS)
            }
        }
    }

    // ── Read aloud ───────────────────────────────────────────────────────────
    //
    // Chapters are served with every sentence marked (`<span data-ra="n">`, see
    // SentenceMarker), numbered as the speech numbers them. In the continuous layout
    // each chapter's section has its own numbering.

    /** Highlights sentence [sentence] of chapter [chapter] and keeps it on screen. Null clears it. */
    fun highlightSentence(chapter: Int, sentence: Int?) {
        if (chapter == readingChapter && sentence == readingSentence) return
        readingChapter = chapter
        readingSentence = sentence
        applyHighlight(follow = sentence != null)
    }

    private fun applyHighlight(follow: Boolean) {
        val flow = layout == BookLayout.CONTINUOUS
        // Another chapter's sentence numbers mean nothing here: just clear.
        val sentence = readingSentence?.takeIf { flow || readingChapter == shownChapter() } ?: -1
        val share = if (layout == BookLayout.SPREAD) 0.5 else 1.0
        evaluateJavascript(
            "(function(c,n,flow,follow,paged,share,top,bottom){var d=document;" +
                "d.querySelectorAll('.$HIGHLIGHT').forEach(function(e){e.classList.remove('$HIGHLIGHT')});" +
                "if(n<0)return -1;" +
                "var root=flow?d.querySelector('section[data-chapter=\"'+c+'\"]'):d.body;if(!root)return -1;" +
                "var s=root.querySelectorAll('[${SentenceMarker.ATTRIBUTE}=\"'+n+'\"]');if(!s.length)return -1;" +
                "s.forEach(function(e){e.classList.add('$HIGHLIGHT')});if(!follow)return -1;" +
                "var r=s[0].getClientRects()[0]||s[0].getBoundingClientRect();" +
                // Paged: the column the sentence starts in, for the app to turn to.
                "if(paged)return Math.floor((r.left+scrollX+1)/(innerWidth*share));" +
                "if(r.top<top||r.bottom>innerHeight-bottom)" +
                "window.scrollTo({top:scrollY+r.top-innerHeight*0.3,behavior:'smooth'});return -1;" +
                "})($readingChapter,$sentence,$flow,$follow,${layout.paged},$share,${ReadingCss.TOP_INSET},$FOLLOW_BOTTOM)",
        ) { result ->
            val column = result?.toIntOrNull() ?: return@evaluateJavascript
            if (column < 0 || !layout.paged) return@evaluateJavascript
            // Following the speech takes over from restoring a position.
            pendingFraction = null
            if (column >= page && column < page + perScreen) return@evaluateJavascript
            measurePages { count ->
                val last = ((count - 1) / perScreen) * perScreen
                showPage(align(column).coerceIn(0, last), count, animate = true, turned = true)
            }
        }
    }

    /** The chapter on screen, outside the continuous layout; -1 in it. */
    private fun shownChapter(): Int =
        if (layout == BookLayout.CONTINUOUS) -1 else loadedChapter?.let { book?.chapterIndexOf(it) } ?: -1

    /**
     * Where reading aloud starts from the page as it is: the first sentence on
     * screen, or the first after it if none is. Reports the chapter (the one shown,
     * or in the continuous layout the one that sentence is in) and the sentence.
     * The sentence is null when no text follows in the chapter shown.
     */
    fun sentenceInView(then: (chapter: Int, sentence: Int?) -> Unit) {
        val shown = shownChapter()
        evaluateJavascript(
            "(function(top){var s=document.querySelectorAll('[${SentenceMarker.ATTRIBUTE}]'),after=null;" +
                "for(var i=0;i<s.length;i++){var rs=s[i].getClientRects();" +
                "for(var j=0;j<rs.length;j++){var r=rs[j];" +
                "if(r.right>0&&r.left<innerWidth&&r.bottom>top&&r.top<innerHeight)return pick(s[i]);" +
                "if(!after&&(r.top>=innerHeight||r.left>=innerWidth))after=s[i];}}" +
                "return after?pick(after):'';" +
                "function pick(e){var sec=e.closest('section[data-chapter]');" +
                "return (sec?sec.dataset.chapter:-1)+','+e.getAttribute('${SentenceMarker.ATTRIBUTE}');}" +
                "})(${ReadingCss.TOP_INSET})",
        ) { raw ->
            val spot = parseSpot(raw, shown)
            when {
                spot != null -> then(spot.first, spot.second)
                shown >= 0 -> then(shown, null)
            }
        }
    }

    /** The sentence the selection starts in, as [sentenceInView] reports it. */
    private fun sentenceAtSelection(then: (chapter: Int, sentence: Int) -> Unit) {
        val shown = shownChapter()
        evaluateJavascript(
            "(function(){var sel=getSelection();if(!sel.rangeCount)return '';" +
                "var n=sel.getRangeAt(0).startContainer,e=n.nodeType===1?n:n.parentElement;" +
                "var at=e&&e.closest('[${SentenceMarker.ATTRIBUTE}]');" +
                // Between sentences, as at a heading's edge: the next one.
                "if(!at){var w=document.createTreeWalker(document.body,NodeFilter.SHOW_ELEMENT);w.currentNode=n;" +
                "while(w.nextNode()){if(w.currentNode.hasAttribute('${SentenceMarker.ATTRIBUTE}')){at=w.currentNode;break;}}}" +
                "if(!at)return '';var sec=at.closest('section[data-chapter]');" +
                "return (sec?sec.dataset.chapter:-1)+','+at.getAttribute('${SentenceMarker.ATTRIBUTE}');})()",
        ) { raw -> parseSpot(raw, shown)?.let { (chapter, sentence) -> then(chapter, sentence) } }
    }

    /** "chapter,sentence" from the page, where a chapter of -1 means the one shown. */
    private fun parseSpot(raw: String?, shown: Int): Pair<Int, Int>? {
        val text = runCatching { JsonParser.parseString(raw).asString }.getOrNull() ?: return null
        val parts = text.split(',')
        if (parts.size != 2) return null
        val chapter = parts[0].toIntOrNull()?.takeIf { it >= 0 } ?: shown
        val sentence = parts[1].toIntOrNull() ?: return null
        return if (chapter >= 0) chapter to sentence else null
    }

    // ── Dictionary ───────────────────────────────────────────────────────────

    /** Adds "Define" to the toolbar Android shows for selected text. */
    override fun startActionMode(callback: ActionMode.Callback, type: Int): ActionMode? =
        super.startActionMode(DefineCallback(callback), type)

    private fun defineSelection(mode: ActionMode) {
        evaluateJavascript("window.getSelection().toString()") { result ->
            // The result is a JSON string, including its quotes.
            val text = runCatching { JsonParser.parseString(result).asString }.getOrNull()
            if (!text.isNullOrBlank()) onDefine(text)
        }
        mode.finish()
    }

    private inner class DefineCallback(private val inner: ActionMode.Callback) : ActionMode.Callback2() {

        /** The WebView rebuilds its menu as the selection changes, so check each time. */
        private fun addDefine(menu: Menu) {
            if (menu.findItem(DEFINE_ITEM) == null) {
                menu.add(Menu.NONE, DEFINE_ITEM, Menu.FIRST, "Define")
                    .setShowAsAction(MenuItem.SHOW_AS_ACTION_ALWAYS)
            }
            if (menu.findItem(READ_ALOUD_ITEM) == null) {
                menu.add(Menu.NONE, READ_ALOUD_ITEM, Menu.FIRST + 1, "Read aloud")
                    .setShowAsAction(MenuItem.SHOW_AS_ACTION_IF_ROOM)
            }
        }

        override fun onCreateActionMode(mode: ActionMode, menu: Menu): Boolean =
            inner.onCreateActionMode(mode, menu).also { addDefine(menu) }

        override fun onPrepareActionMode(mode: ActionMode, menu: Menu): Boolean {
            val changed = inner.onPrepareActionMode(mode, menu)
            addDefine(menu)
            return changed
        }

        override fun onActionItemClicked(mode: ActionMode, item: MenuItem): Boolean {
            when (item.itemId) {
                DEFINE_ITEM -> defineSelection(mode)
                READ_ALOUD_ITEM -> {
                    sentenceAtSelection { chapter, sentence -> onReadAloudFrom(chapter, sentence) }
                    // Evaluated in order, so the selection is read before it's cleared.
                    evaluateJavascript("getSelection().removeAllRanges()", null)
                    mode.finish()
                }
                else -> return inner.onActionItemClicked(mode, item)
            }
            return true
        }

        override fun onDestroyActionMode(mode: ActionMode) = inner.onDestroyActionMode(mode)

        override fun onGetContentRect(mode: ActionMode, view: View, outRect: android.graphics.Rect) {
            if (inner is ActionMode.Callback2) inner.onGetContentRect(mode, view, outRect)
            else super.onGetContentRect(mode, view, outRect)
        }
    }

    override fun onDetachedFromWindow() {
        removeCallbacks(restoreTick)
        removeCallbacks(flowCheck)
        loader.shutdownNow()
        super.onDetachedFromWindow()
    }

    private inner class BookClient : WebViewClient() {
        /** A reload, for a new theme or font, loses the highlight: put it back. */
        override fun onPageFinished(view: WebView, url: String) {
            if (readingSentence != null) applyHighlight(follow = true)
        }

        override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse {
            val uri = request.url
            val book = book
            if (uri.host != BOOK_HOST || book == null) return refused()
            val path = uri.path?.removePrefix("/") ?: return refused()

            if (path.startsWith(BUNDLED_FONT_PATH)) return bundledFont(path.removePrefix(BUNDLED_FONT_PATH))

            if (path.startsWith(FLOW_PATH)) {
                val index = path.removePrefix(FLOW_PATH).toIntOrNull() ?: return refused()
                val chapter = book.chapters.getOrNull(index) ?: return refused()
                val bytes = runCatching { book.read(chapter.path) }.getOrNull() ?: CHAPTER_FAILED.toByteArray()
                val section = EpubParser.flowSection(
                    index, chapter.path, EpubParser.decodeText(bytes), BOOK_HOST, markSentences = true,
                )
                return html(EpubParser.renderFlow(section, themeCss))
            }

            // Served as HTML rather than XHTML: one stray character in strict XML
            // would replace the whole chapter with a parse error.
            if (book.chapterIndexOf(path) != null) {
                // When streaming, a dropped connection shouldn't look like a blank page.
                val bytes = runCatching { book.read(path) }.getOrNull()
                    ?: CHAPTER_FAILED.toByteArray()
                return html(EpubParser.renderChapter(EpubParser.decodeText(bytes), themeCss, markSentences = true))
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
            if (layout != BookLayout.CONTINUOUS && path.equals(loadedChapter, ignoreCase = true)) return false
            onLinkToChapter(target)
            return true
        }

        private fun html(text: String) = WebResourceResponse(
            "text/html",
            "utf-8",
            200,
            "OK",
            mapOf("Content-Security-Policy" to EpubParser.CONTENT_SECURITY_POLICY),
            ByteArrayInputStream(text.toByteArray()),
        )

        /** Only the fonts the app bundles, by exact name. */
        private fun bundledFont(name: String): WebResourceResponse {
            if (name !in BUNDLED_FONT_FILES) return refused()
            val stream = runCatching { context.assets.open("fonts/$name") }.getOrNull() ?: return refused()
            return WebResourceResponse(mimeTypeOf(name), null, stream)
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
        /** The continuous layout's document, served by the app. No book path starts so. */
        const val FLOW_PATH = "__rekindle__/flow/"
        const val DEFAULT_FONT_SIZE = 16f
        const val DEFINE_ITEM = 0x52454B44
        const val READ_ALOUD_ITEM = 0x52454B52
        const val HIGHLIGHT = READ_ALOUD_HIGHLIGHT
        /** Room kept clear at the bottom when following the speech: the controls. */
        const val FOLLOW_BOTTOM = 80
        const val RESTORE_WINDOW_MS = 2000L
        const val RESTORE_TICK_MS = 100L
        const val FLOW_CHECK_MS = 150L
        /** The share of the page's width, on each side, that a tap turns the page. */
        const val TURN_ZONE = 0.3f
        const val FLING_VELOCITY = 800f
    }
}
