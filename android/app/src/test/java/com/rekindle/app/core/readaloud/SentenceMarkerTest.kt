package com.rekindle.app.core.readaloud

import com.rekindle.app.core.epub.EpubParser
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SentenceMarkerTest {

    @Test
    fun `splits prose and dialogue into sentences`() {
        val marked = SentenceMarker.mark(
            "<p>It is a truth universally acknowledged. \"My dear Mr. Bennet,\" said " +
                "his lady, \"have you heard?\" Mr. Bennet replied that he had not.</p>",
        )
        assertEquals(
            listOf(
                "It is a truth universally acknowledged.",
                "\"My dear Mr. Bennet,\" said his lady, \"have you heard?\"",
                "Mr. Bennet replied that he had not.",
            ),
            marked.sentences,
        )
    }

    @Test
    fun `titles and initials do not end a sentence, but I does`() {
        val marked = SentenceMarker.mark("<p>Dr. Watson met J. R. Smith at St. Paul’s. So did I. Then we left.</p>")
        assertEquals(listOf("Dr. Watson met J. R. Smith at St. Paul’s.", "So did I.", "Then we left."), marked.sentences)
    }

    @Test
    fun `a heading or paragraph always ends a sentence`() {
        val marked = SentenceMarker.mark("<h1>Chapter One</h1><p>No full stop here</p><p>Nor here<br>or here</p>")
        assertEquals(listOf("Chapter One", "No full stop here", "Nor here", "or here"), marked.sentences)
    }

    @Test
    fun `a sentence across inline elements keeps one number`() {
        val marked = SentenceMarker.mark("<p>She said <i>never again</i> and left. Then rain.</p>")
        assertEquals(listOf("She said never again and left.", "Then rain."), marked.sentences)
        assertEquals(3, Regex("data-ra=\"0\"").findAll(marked.html).count())
        assertTrue("<i><span data-ra=\"0\">never again</span></i>" in marked.html)
    }

    @Test
    fun `scripts, styles and pictures are not read, and keep their case`() {
        val marked = SentenceMarker.mark(
            "<style>p{}</style><p>Read me.</p><svg viewBox=\"0 0 1 1\"><text>Not me</text></svg>",
        )
        assertEquals(listOf("Read me."), marked.sentences)
        assertTrue("viewBox" in marked.html)
        assertFalse("data-ra=\"1\"" in marked.html)
    }

    @Test
    fun `a scene break is a sentence on the page, but nothing to say`() {
        val marked = SentenceMarker.mark("<p>Before.</p><p>* * *</p><p>After.</p>")
        assertEquals(3, marked.sentences.size)
        assertTrue(marked.speakable(0))
        assertFalse(marked.speakable(1))
    }

    @Test
    fun `starts find where to begin reading from a position`() {
        val marked = SentenceMarker.mark("<p>One one one. Two two two.</p><p>Three three. Four.</p>")
        assertEquals(0, marked.sentenceAt(0f))
        assertEquals(3, marked.sentenceAt(1f))
        assertTrue(marked.starts.zipWithNext().all { (a, b) -> a < b })
    }

    @Test
    fun `the page and the speech number sentences alike`() {
        val chapter = "<html><head><title/></head><body><p>First. Second.</p><a id=\"x\"/><p>Third.</p></body></html>"
        val page = EpubParser.renderChapter(chapter, "", markSentences = true)
        val speech = EpubParser.chapterSentences(chapter)
        assertEquals(listOf("First.", "Second.", "Third."), speech.sentences)
        assertTrue("<span data-ra=\"2\">Third.</span>" in page)
        // Unmarked, the chapter is served as it was.
        assertFalse("data-ra" in EpubParser.renderChapter(chapter, ""))
    }

    @Test
    fun `long text is split for the engine between words`() {
        val parts = ReadAloud.split("aaaa bbbb cccc dddd", 10)
        assertEquals(listOf("aaaa bbbb", "cccc dddd"), parts)
        assertEquals(listOf("short"), ReadAloud.split("short", 10))
    }
}
