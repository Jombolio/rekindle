package com.rekindle.app.core.prefs

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ReadingStyleTest {

    @Test
    fun `reads back what was saved`() {
        val style = ReadingStyle(
            layout = BookLayout.SPREAD,
            lineHeight = 2f,
            letterSpacing = 0.05f,
            wordSpacing = 0.2f,
            paragraphSpacing = 1f,
            measure = 40f,
            align = BookAlign.JUSTIFY,
            bold = true,
            animations = false,
            ruler = true,
        )
        assertEquals(style, ReadingStyle.fromJson(style.toJson()))
    }

    @Test
    fun `missing, unreadable or out-of-range values fall back safely`() {
        assertEquals(ReadingStyle(), ReadingStyle.fromJson(null))
        assertEquals(ReadingStyle(), ReadingStyle.fromJson("not json"))
        val wild = ReadingStyle.fromJson("""{"layout":"SIDEWAYS","lineHeight":9,"measure":-3,"bold":"yes"}""")
        assertEquals(BookLayout.SCROLL, wild.layout)
        assertEquals(ReadingStyle.LINE_HEIGHT.endInclusive, wild.lineHeight)
        assertEquals(ReadingStyle.MEASURE.start, wild.measure)
        assertFalse(wild.bold)
    }

    @Test
    fun `spacing and bold override the book, alignment leaves its centred text`() {
        val css = ReadingCss.css(
            ReadingStyle(letterSpacing = 0.1f, paragraphSpacing = 1.5f, align = BookAlign.JUSTIFY, bold = true),
        )
        assertTrue("letter-spacing:0.1em !important" in css)
        assertTrue("margin-bottom:1.5em !important" in css)
        assertTrue("font-weight:700 !important" in css)
        // No !important: a book's own class, such as a centred title, still wins.
        assertTrue("html body p,html body li,html body blockquote,html body dd{text-align:justify;" in css)
    }

    @Test
    fun `untouched spacing leaves the book's own`() {
        val css = ReadingCss.css(ReadingStyle())
        assertFalse("letter-spacing" in css)
        assertFalse("word-spacing" in css)
        assertFalse("margin-bottom" in css)
        assertFalse("text-align" in css)
    }

    @Test
    fun `paged layouts lay chapters out in screen-wide columns`() {
        val single = ReadingCss.css(ReadingStyle(layout = BookLayout.PAGE))
        assertTrue("column-width:min(36.0em,calc(100vw - 32px))" in single)
        assertTrue("overflow:hidden" in single)
        val spread = ReadingCss.css(ReadingStyle(layout = BookLayout.SPREAD))
        assertTrue("calc(50vw - 32px)" in spread)
        assertFalse("column-width" in ReadingCss.css(ReadingStyle(layout = BookLayout.CONTINUOUS)))
    }
}
