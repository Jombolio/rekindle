package com.rekindle.app.core.epub

import org.w3c.dom.Element
import java.io.Closeable
import java.io.File
import java.io.InputStream
import java.net.URLDecoder
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import javax.xml.parsers.DocumentBuilderFactory

data class EpubChapter(val title: String, val path: String)

/** A book the reader can show, from a downloaded file or streamed from the server. */
interface ReaderBook : Closeable {
    val title: String
    val chapters: List<EpubChapter>

    /** Opens the file at [path] inside the book, or returns null if it can't be had. */
    fun open(path: String): InputStream?

    fun read(path: String): ByteArray? = open(path)?.use { it.readBytes() }

    fun chapterIndexOf(path: String): Int? {
        val wanted = EpubParser.normalizePath(path)
        return chapters.indexOfFirst { it.path.equals(wanted, ignoreCase = true) }
            .takeIf { it >= 0 }
    }
}

/**
 * An open EPUB. Files are read from the archive when asked for rather than held
 * in memory, so an illustrated book doesn't cost its full size in RAM. Must be
 * closed when finished with.
 */
class EpubBook internal constructor(
    override val title: String,
    override val chapters: List<EpubChapter>,
    private val zip: ZipFile,
    private val entries: Map<String, ZipEntry>,
) : ReaderBook {

    override fun open(path: String): InputStream? {
        val entry = entries[EpubParser.normalizePath(path).lowercase()] ?: return null
        return zip.getInputStream(entry)
    }

    override fun close() = zip.close()
}

object EpubParser {

    /** Whether [file] is a ZIP container, which every EPUB is. Copies of MOBI files
     *  downloaded by older versions are not. */
    fun isEpubFile(file: File): Boolean = runCatching {
        file.inputStream().use { it.read() == 0x50 && it.read() == 0x4B }
    }.getOrDefault(false)

    fun open(file: File): EpubBook {
        val zip = ZipFile(file)
        try {
            val entries = zip.entries().asSequence()
                .filterNot { it.isDirectory }
                .associateBy { normalizePath(it.name).lowercase() }

            fun bytesOf(path: String): ByteArray? =
                entries[normalizePath(path).lowercase()]?.let { e ->
                    zip.getInputStream(e).use { it.readBytes() }
                }

            val containerDoc = parseXml(bytesOf("META-INF/container.xml") ?: error("EPUB missing META-INF/container.xml"))
            val opfPath = containerDoc.getElementsByTagName("rootfile").let { nodes ->
                (0 until nodes.length).firstNotNullOfOrNull { i ->
                    (nodes.item(i) as? Element)?.getAttribute("full-path")
                }
            } ?: error("EPUB: cannot find OPF path")

            val opfDoc = parseXml(bytesOf(opfPath) ?: error("EPUB missing OPF: $opfPath"))

            val titleNode = opfDoc.getElementsByTagName("dc:title").item(0)
            val bookTitle = titleNode?.textContent?.trim() ?: "Unknown"

            // id → href manifest
            val manifest = mutableMapOf<String, String>()
            val items = opfDoc.getElementsByTagName("item")
            for (i in 0 until items.length) {
                val el = items.item(i) as? Element ?: continue
                val id = el.getAttribute("id")
                val href = el.getAttribute("href")
                if (id.isNotBlank() && href.isNotBlank()) manifest[id] = href
            }

            // Spine order
            val spine = opfDoc.getElementsByTagName("itemref")
            val chapters = mutableListOf<EpubChapter>()
            for (i in 0 until spine.length) {
                val el = spine.item(i) as? Element ?: continue
                val idref = el.getAttribute("idref").takeIf { it.isNotBlank() } ?: continue
                val href = manifest[idref] ?: continue
                val path = resolve(opfPath, href)
                val html = bytesOf(path)?.let(::decodeText) ?: continue
                chapters += EpubChapter(
                    title = extractTitle(html) ?: path.substringAfterLast('/'),
                    path = path,
                )
            }

            return EpubBook(bookTitle, chapters, zip, entries)
        } catch (e: Exception) {
            zip.close()
            throw e
        }
    }

    /**
     * Resolves an href found in the document at [fromPath]. Hrefs are URIs:
     * percent-encoded and possibly carrying a #fragment, while paths in the archive
     * are raw.
     */
    fun resolve(fromPath: String, href: String): String {
        val decoded = decodeHref(href.substringBefore('#'))
        if (decoded.startsWith("/")) return normalizePath(decoded)
        val dir = if ('/' in fromPath) fromPath.substringBeforeLast('/') + "/" else ""
        return normalizePath("$dir$decoded")
    }

    /** URLDecoder form-decodes '+' to space, which is wrong for URIs — protect it. */
    private fun decodeHref(href: String): String =
        runCatching { URLDecoder.decode(href.replace("+", "%2B"), "UTF-8") }.getOrDefault(href)

    /** Resolves ./ and ../ segments and drops empty ones so hrefs and zip entry names compare equal. */
    fun normalizePath(path: String): String {
        val parts = mutableListOf<String>()
        for (seg in path.replace('\\', '/').split('/')) when (seg) {
            "", "." -> {}
            ".." -> parts.removeLastOrNull()
            else -> parts.add(seg)
        }
        return parts.joinToString("/")
    }

    private fun parseXml(bytes: ByteArray): org.w3c.dom.Document =
        DocumentBuilderFactory.newInstance()
            .also { f ->
                f.isNamespaceAware = true
                // EPUBs are untrusted input — never resolve external entities (XXE).
                f.isExpandEntityReferences = false
                f.isXIncludeAware = false
                runCatching { f.setFeature("http://xml.org/sax/features/external-general-entities", false) }
                runCatching { f.setFeature("http://xml.org/sax/features/external-parameter-entities", false) }
                runCatching { f.setFeature("http://apache.org/xml/features/nonvalidating/load-external-dtd", false) }
            }
            .newDocumentBuilder()
            .parse(bytes.inputStream())

    /** Decodes book text using its BOM or XML declaration. Most books are UTF-8, but
     *  older ones are often UTF-16 or Latin-1. */
    fun decodeText(bytes: ByteArray): String {
        fun at(i: Int) = bytes.getOrElse(i) { 0 }.toInt() and 0xFF
        if (at(0) == 0xEF && at(1) == 0xBB && at(2) == 0xBF) return String(bytes, 3, bytes.size - 3, Charsets.UTF_8)
        if (at(0) == 0xFF && at(1) == 0xFE) return String(bytes, 2, bytes.size - 2, Charsets.UTF_16LE)
        if (at(0) == 0xFE && at(1) == 0xFF) return String(bytes, 2, bytes.size - 2, Charsets.UTF_16BE)

        val head = String(bytes, 0, minOf(bytes.size, 200), Charsets.ISO_8859_1)
        val declared = Regex("""encoding\s*=\s*["']([\w-]+)["']""").find(head)?.groupValues?.get(1)?.lowercase()
        return when (declared) {
            "iso-8859-1", "latin1" -> String(bytes, Charsets.ISO_8859_1)
            "windows-1252" -> String(bytes, charset("windows-1252"))
            else -> String(bytes, Charsets.UTF_8)
        }
    }

    /** The chapter's title: its first heading, else its `<title>`. Many books repeat
     *  the book's name in every `<title>`, so a heading is the better guide. */
    fun extractTitle(html: String): String? {
        fun clean(raw: String?) = raw?.replace(TAG, "")?.trim()?.takeIf { it.isNotEmpty() }
        return clean(HEADING.find(html)?.groupValues?.get(1)) ?: clean(TITLE.find(html)?.groupValues?.get(1))
    }

    /**
     * Rebuilds a chapter document for the WebView, which parses it as HTML rather
     * than XHTML. Only the stylesheets and body are carried over: an XHTML-style
     * `<title/>` in the original head would swallow the whole page. [themeCss] comes
     * last so the reader's theme wins.
     */
    fun renderChapter(html: String, themeCss: String): String {
        val body = BODY.find(html)
        val head = html.substring(0, body?.range?.first ?: 0)
        val links = LINK.findAll(head).map { it.value }.filter { "stylesheet" in it.lowercase() }
        val styles = STYLE.findAll(head).map { it.value }
        val bodyAttributes = body?.groupValues?.get(1).orEmpty()
        val content = expandSelfClosingTags(body?.groupValues?.get(2) ?: html).replace(SCRIPT, "")
        return buildString {
            append("<!DOCTYPE html><html><head><meta charset=\"utf-8\">")
            append("<meta http-equiv=\"Content-Security-Policy\" content=\"").append(CONTENT_SECURITY_POLICY).append("\">")
            append("<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">")
            links.forEach { append(it) }
            styles.forEach { append(expandSelfClosingStyle(it)) }
            append("<style>").append(themeCss).append("</style></head>")
            append("<body").append(bodyAttributes).append(">").append(content).append("</body></html>")
        }
    }

    /**
     * One chapter as a section of the continuous layout's document. Its links and
     * images point at absolute addresses on [host], since the document's own address
     * belongs to none of its chapters. Its stylesheets come along inside the section,
     * where browsers apply them as they would in the head.
     */
    fun flowSection(index: Int, path: String, html: String, host: String): String {
        val body = BODY.find(html)
        val head = html.substring(0, body?.range?.first ?: 0)
        val links = LINK.findAll(head).map { it.value }.filter { "stylesheet" in it.lowercase() }
        val styles = STYLE.findAll(head).map { it.value }.map { expandSelfClosingStyle(it) }
        val content = expandSelfClosingTags(body?.groupValues?.get(2) ?: html).replace(SCRIPT, "")
        return buildString {
            append("<section data-chapter=\"").append(index).append("\">")
            links.forEach { append(absoluteUrls(it, path, host)) }
            styles.forEach { append(it) }
            append(absoluteUrls(content, path, host))
            append("</section>")
        }
    }

    /** The continuous layout's document, opening with [firstSection]. */
    fun renderFlow(firstSection: String, themeCss: String): String = buildString {
        append("<!DOCTYPE html><html><head><meta charset=\"utf-8\">")
        append("<meta http-equiv=\"Content-Security-Policy\" content=\"").append(CONTENT_SECURITY_POLICY).append("\">")
        append("<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">")
        append("<style>section[data-chapter]{display:block;padding-bottom:3em;}</style>")
        append("<style>").append(themeCss).append("</style></head><body>")
        append(firstSection)
        append("</body></html>")
    }

    /**
     * Rewrites relative `src` and `href` values against [path], as absolute addresses
     * on [host]. Fragments within the chapter, and addresses with a scheme, are left
     * as they are.
     */
    fun absoluteUrls(html: String, path: String, host: String): String = URL_ATTRIBUTE.replace(html) { m ->
        val (name, quote, value) = m.destructured
        val trimmed = value.trim()
        if (trimmed.isEmpty() || trimmed.startsWith("#") || SCHEME.containsMatchIn(trimmed)) return@replace m.value
        val fragment = trimmed.substringAfter('#', "").let { if (it.isEmpty()) "" else "#$it" }
        val resolved = resolve(path, trimmed)
        "$name=$quote" + "https://$host/$resolved$fragment" + quote
    }

    private fun expandSelfClosingStyle(style: String) =
        if (style.trimEnd().endsWith("/>")) "" else style

    /** `<a id="x"/>` is valid XHTML, but an HTML parser reads it as an unclosed `<a>`
     *  that swallows what follows. */
    fun expandSelfClosingTags(html: String): String = SELF_CLOSING.replace(html) { m ->
        val tag = m.groupValues[1]
        if (tag.lowercase() in VOID_TAGS) m.value
        else "<$tag${m.groupValues[2]}></$tag>"
    }

    /**
     * The WebView has JavaScript on only so the app can read the selected text. Books
     * never get to run any: scripts in a book are removed and refused by this policy.
     */
    const val CONTENT_SECURITY_POLICY = "script-src 'none'; object-src 'none'; base-uri 'none'"

    private val SCRIPT = Regex("<script\\b.*?(?:</script\\s*>|\\z)", setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL))
    private val TAG = Regex("<[^>]+>")
    private val HEADING = Regex("<h[1-3]\\b[^>]*>(.*?)</h[1-3]\\s*>", setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL))
    private val TITLE = Regex("<title[^>]*>(.*?)</title>", setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL))
    private val BODY = Regex("<body\\b([^>]*)>(.*)</body\\s*>", setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL))
    private val LINK = Regex("<link\\b[^>]*>", RegexOption.IGNORE_CASE)
    private val STYLE = Regex("<style\\b[^>]*?(?:/>|>.*?</style\\s*>)", setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL))
    private val SELF_CLOSING = Regex("<([a-zA-Z][\\w:-]*)((?:[^<>\"]|\"[^\"]*\")*?)/>")
    private val VOID_TAGS = setOf("img", "br", "hr", "input", "meta", "link", "col")
    private val URL_ATTRIBUTE = Regex("""\b((?:xlink:)?href|src|poster)\s*=\s*(["'])(.*?)\2""", RegexOption.IGNORE_CASE)
    private val SCHEME = Regex("^[a-zA-Z][a-zA-Z0-9+.-]*:")
}
