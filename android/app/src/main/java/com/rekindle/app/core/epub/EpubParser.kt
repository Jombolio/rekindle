package com.rekindle.app.core.epub

import org.jsoup.Jsoup
import org.w3c.dom.Element
import java.io.File
import java.util.zip.ZipFile
import javax.xml.parsers.DocumentBuilderFactory

data class EpubChapter(val title: String, val html: String)
data class EpubBook(val title: String, val chapters: List<EpubChapter>)

object EpubParser {

    fun parse(file: File): EpubBook {
        ZipFile(file).use { zip ->
            val containerEntry = zip.getEntry("META-INF/container.xml")
                ?: error("EPUB missing META-INF/container.xml")

            val containerDoc = parseXml(zip.getInputStream(containerEntry).readBytes())
            val opfPath = containerDoc.getElementsByTagName("rootfile").let { nodes ->
                (0 until nodes.length).firstNotNullOfOrNull { i ->
                    (nodes.item(i) as? Element)?.getAttribute("full-path")
                }
            } ?: error("EPUB: cannot find OPF path")

            val opfDir = if ('/' in opfPath) opfPath.substringBeforeLast('/') + "/" else ""
            val opfEntry = zip.getEntry(opfPath) ?: error("EPUB missing OPF: $opfPath")
            val opfDoc = parseXml(zip.getInputStream(opfEntry).readBytes())

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
                val fullPath = "$opfDir$href"
                val entry = zip.getEntry(fullPath)
                    ?: zip.getEntry(fullPath.removePrefix("/"))
                    ?: continue
                val html = zip.getInputStream(entry).readBytes().toString(Charsets.UTF_8)
                val chapterTitle = extractTitle(html) ?: href.substringAfterLast('/')
                chapters += EpubChapter(title = chapterTitle, html = html)
            }

            return EpubBook(title = bookTitle, chapters = chapters)
        }
    }

    private fun parseXml(bytes: ByteArray): org.w3c.dom.Document =
        DocumentBuilderFactory.newInstance().also { it.isNamespaceAware = true }
            .newDocumentBuilder()
            .parse(bytes.inputStream())

    private fun extractTitle(html: String): String? =
        Jsoup.parse(html).title().takeIf { it.isNotBlank() }
}
