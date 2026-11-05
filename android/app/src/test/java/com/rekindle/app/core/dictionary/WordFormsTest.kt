package com.rekindle.app.core.dictionary

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WordFormsTest {

    @Test
    fun `tidies a selection into a headword`() {
        assertEquals("dogs", WordForms.normalize("  Dogs, "))
        assertEquals("dog", WordForms.normalize("“dog’s”"))
        assertEquals("ice cream", WordForms.normalize("Ice\n cream."))
        assertEquals("well-known", WordForms.normalize("well-known"))
    }

    @Test
    fun `a sentence or nothing at all is not a word`() {
        assertNull(WordForms.normalize("the quick brown fox jumps"))
        assertNull(WordForms.normalize(" ... "))
    }

    @Test
    fun `undoes inflections, keeping the word itself first`() {
        assertEquals("running", WordForms.stems("running").first())
        assertTrue("run" !in WordForms.stems("running")) // Doubled consonants aren't a rule.
        assertTrue("make" in WordForms.stems("making"))
        assertTrue("walk" in WordForms.stems("walked"))
        assertTrue("city" in WordForms.stems("cities"))
        assertTrue("box" in WordForms.stems("boxes"))
        assertTrue("fireman" in WordForms.stems("firemen"))
        assertTrue("large" in WordForms.stems("larger"))
    }

    @Test
    fun `a suffix can't be the whole word`() {
        assertEquals(listOf("s"), WordForms.stems("s"))
    }
}
