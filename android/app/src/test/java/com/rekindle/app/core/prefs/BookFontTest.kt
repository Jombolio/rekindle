package com.rekindle.app.core.prefs

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class BookFontTest {

    @Test
    fun `reads back what was saved and survives an unknown value`() {
        BookFont.entries.forEach { assertEquals(it, BookFont.parse(it.name)) }
        assertEquals(BookFont.ORIGINAL, BookFont.parse("COMIC_SANS"))
        assertEquals(BookFont.ORIGINAL, BookFont.parse(null))
    }

    @Test
    fun `cycling goes through every font and comes back`() {
        val seen = generateSequence(BookFont.ORIGINAL) { it.next }.take(BookFont.entries.size).toSet()
        assertEquals(BookFont.entries.toSet(), seen)
        assertEquals(BookFont.ORIGINAL, BookFont.MONO.next)
    }

    @Test
    fun `the book's own fonts are left alone, and a choice overrides them`() {
        assertEquals("", BookFont.ORIGINAL.css)
        assertTrue("sans-serif !important" in BookFont.SANS.css)
    }
}
