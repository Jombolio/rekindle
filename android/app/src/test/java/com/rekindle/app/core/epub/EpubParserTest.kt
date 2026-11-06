package com.rekindle.app.core.epub

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class EpubParserTest {

    private fun epub(vararg files: Pair<String, String>): File {
        val file = File.createTempFile("book", ".epub")
        file.deleteOnExit()
        ZipOutputStream(file.outputStream()).use { zip ->
            val container = """<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles></container>"""
            for ((name, text) in listOf("META-INF/container.xml" to container) + files) {
                zip.putNextEntry(ZipEntry(name))
                zip.write(text.toByteArray())
                zip.closeEntry()
            }
        }
        return file
    }

    private fun opf(vararg hrefs: String): String {
        val items = hrefs.withIndex().joinToString("") { (i, h) -> """<item id="c$i" href="$h"/>""" }
        val refs = hrefs.indices.joinToString("") { """<itemref idref="c$it"/>""" }
        return """<package xmlns="http://www.idpf.org/2007/opf"><manifest>$items</manifest><spine>$refs</spine></package>"""
    }

    @Test
    fun `reads chapters in spine order and skips missing files`() {
        EpubParser.open(
            epub(
                "OPS/book.opf" to opf("b.xhtml", "gone.xhtml", "a.xhtml"),
                "OPS/a.xhtml" to "<html><body><h1>Alpha</h1></body></html>",
                "OPS/b.xhtml" to "<html><head><title>Book</title></head><body><h2>Beta</h2></body></html>",
            ),
        ).use { book ->
            assertEquals(listOf("Beta", "Alpha"), book.chapters.map { it.title })
            assertEquals(1, book.chapterIndexOf("ops/A.XHTML"))
            assertNull(book.chapterIndexOf("OPS/none.xhtml"))
        }
    }

    @Test
    fun `reads other files from the book by path`() {
        EpubParser.open(
            epub(
                "OPS/book.opf" to opf("text/a.xhtml"),
                "OPS/text/a.xhtml" to "<html><body><img src=\"../img/pic.png\"/></body></html>",
                "OPS/img/pic.png" to "image",
            ),
        ).use { book ->
            val path = EpubParser.resolve(book.chapters[0].path, "../img/pic.png")
            assertEquals("OPS/img/pic.png", path)
            assertNotNull(book.read(path))
            assertNull(book.read("OPS/img/none.png"))
        }
    }

    @Test
    fun `recognises what is and is not an epub`() {
        assertTrue(EpubParser.isEpubFile(epub("OPS/book.opf" to opf())))
        val mobi = File.createTempFile("book", ".mobi").apply {
            deleteOnExit()
            writeText("not a zip")
        }
        assertFalse(EpubParser.isEpubFile(mobi))
        assertFalse(EpubParser.isEpubFile(File("does-not-exist.epub")))
    }

    @Test
    fun `resolve decodes hrefs without treating plus as a space`() {
        assertEquals("OPS/img/my pic+1.png", EpubParser.resolve("OPS/text/a.xhtml", "../img/my%20pic+1.png#x"))
    }

    @Test
    fun `expands self-closing tags except void ones`() {
        assertEquals(
            "<a id=\"x\"></a><br/><img src=\"a/b.png\"/><div></div>",
            EpubParser.expandSelfClosingTags("<a id=\"x\"/><br/><img src=\"a/b.png\"/><div/>"),
        )
        assertEquals("<a id=\"\$1\"></a>", EpubParser.expandSelfClosingTags("<a id=\"\$1\"/>"))
    }

    @Test
    fun `rendering survives an XHTML head and puts the theme last`() {
        val html = EpubParser.renderChapter(
            "<html><head><title/><style type=\"text/css\"/><link rel=\"stylesheet\" href=\"s.css\"/></head>" +
                "<BODY class=\"c\"><p/>x</BODY></html>",
            "THEME",
        )
        assertFalse("<title" in html)
        assertTrue("<body class=\"c\"><p></p>x</body>" in html)
        assertTrue(html.indexOf("s.css") < html.indexOf("THEME"))
    }

    @Test
    fun `books can't run scripts`() {
        val html = EpubParser.renderChapter(
            "<html><body><p>x</p><script>steal()</script><SCRIPT src=\"a.js\"></SCRIPT><script>open(</body></html>",
            "T",
        )
        assertFalse("steal" in html)
        assertFalse("a.js" in html)
        assertTrue("script-src 'none'" in html)
        assertTrue(html.indexOf("Content-Security-Policy") < html.indexOf("<body"))
    }

    @Test
    fun `decodes text by BOM and declared encoding`() {
        assertEquals("é", EpubParser.decodeText(byteArrayOf(0xFF.toByte(), 0xFE.toByte(), 0xE9.toByte(), 0)))
        assertEquals(
            "é",
            EpubParser.decodeText(byteArrayOf(0xEF.toByte(), 0xBB.toByte(), 0xBF.toByte(), 0xC3.toByte(), 0xA9.toByte())),
        )
        val latin = "<?xml version=\"1.0\" encoding=\"iso-8859-1\"?>".toByteArray() + 0xE9.toByte()
        assertTrue(EpubParser.decodeText(latin).endsWith("é"))
    }

    @Test
    fun `continuous chapters point their links and images at absolute addresses`() {
        val html = """<img src="../images/a.png"/><a href="c2.xhtml#n1">note</a>""" +
            """<a href="#here">here</a><a href="https://example.com/">out</a>"""
        val out = EpubParser.absoluteUrls(html, "OPS/text/c1.xhtml", "book.test")
        assertTrue("src=\"https://book.test/OPS/images/a.png\"" in out)
        assertTrue("href=\"https://book.test/OPS/text/c2.xhtml#n1\"" in out)
        assertTrue("href=\"#here\"" in out)
        assertTrue("href=\"https://example.com/\"" in out)
    }

    @Test
    fun `a continuous chapter is a section that keeps its stylesheets`() {
        val html = """<html><head><link rel="stylesheet" href="s.css"/><script>x()</script></head>""" +
            """<body><p>Hi</p><script>bad()</script></body></html>"""
        val section = EpubParser.flowSection(3, "OPS/c3.xhtml", html, "book.test")
        assertTrue(section.startsWith("<section data-chapter=\"3\">"))
        assertTrue("https://book.test/OPS/s.css" in section)
        assertTrue("<p>Hi</p>" in section)
        assertFalse("bad()" in section)
    }
}
