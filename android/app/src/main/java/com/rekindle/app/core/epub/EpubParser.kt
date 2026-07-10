package com.rekindle.app.core.epub

import org.jsoup.Jsoup
import org.w3c.dom.Element
import java.io.InputStream
import java.net.URLDecoder
import java.util.zip.ZipInputStream
import javax.xml.parsers.DocumentBuilderFactory

data class EpubChapter(val title: String, val html: String)
data class EpubBook(val title: String, val chapters: List<EpubChapter>)

object EpubParser {

    fun parse(stream: InputStream): EpubBook {
        val files = mutableMapOf<String, ByteArray>()
        ZipInputStream(stream.buffered()).use { zip ->
            var entry = zip.nextEntry
            while (entry != null) {
                if (!entry.isDirectory) {
                    files[normalizePath(entry.name)] = zip.readBytes()
                }
                entry = zip.nextEntry
            }
        }

        val containerBytes = files["META-INF/container.xml"] ?: error("EPUB missing META-INF/container.xml")
        val containerDoc = parseXml(containerBytes)
        val opfPath = containerDoc.getElementsByTagName("rootfile").let { nodes ->
            (0 until nodes.length).firstNotNullOfOrNull { i ->
                (nodes.item(i) as? Element)?.getAttribute("full-path")
            }
        } ?: error("EPUB: cannot find OPF path")

        val opfDir = if ('/' in opfPath) opfPath.substringBeforeLast('/') + "/" else ""
        val opfBytes = files[opfPath] ?: error("EPUB missing OPF: $opfPath")
        val opfDoc = parseXml(opfBytes)

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
            // Manifest hrefs are URIs (percent-encoded, may carry a #fragment and
            // ../ segments); zip entry names are raw paths — decode before lookup
            // or chapters with spaces in their filenames are silently dropped.
            val decoded = decodeHref(href.substringBefore('#'))
            val htmlBytes = files[normalizePath("$opfDir$decoded")]
                ?: files[normalizePath("$opfDir$href")]
                ?: continue
            val html = htmlBytes.toString(Charsets.UTF_8)
            val chapterTitle = extractTitle(html) ?: href.substringAfterLast('/')
            chapters += EpubChapter(title = chapterTitle, html = html)
        }

        return EpubBook(title = bookTitle, chapters = chapters)
    }

    /** URLDecoder form-decodes '+' to space, which is wrong for URIs — protect it. */
    private fun decodeHref(href: String): String =
        runCatching { URLDecoder.decode(href.replace("+", "%2B"), "UTF-8") }.getOrDefault(href)

    /** Resolves ./ and ../ segments and drops empty ones so hrefs and zip entry names compare equal. */
    private fun normalizePath(path: String): String {
        val parts = mutableListOf<String>()
        for (seg in path.split('/')) when (seg) {
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

    private fun extractTitle(html: String): String? =
        Jsoup.parse(html).title().takeIf { it.isNotBlank() }
}
