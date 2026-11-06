package com.rekindle.app.domain.model

import org.junit.Assert.assertEquals
import org.junit.Test

class MediaLabelTest {

    private fun archive(path: String = "Series/Chapter 1.cbz", format: String = "cbz", title: String = "Chapter 1") =
        Media(
            id = "a",
            title = title,
            sortTitle = title,
            format = format,
            mediaType = "archive",
            relativePath = path,
            parentId = null,
            pageCount = null,
            libraryId = "l",
        )

    @Test
    fun `extensions are off unless asked for`() {
        assertEquals("Chapter 1", archive().label(showExtension = false))
        assertEquals("Chapter 1.cbz", archive().label(showExtension = true))
    }

    @Test
    fun `the extension is the file's own, as written`() {
        assertEquals("Dune.AZW3", archive("Books/Dune.AZW3", "azw3", "Dune").label(showExtension = true))
    }

    @Test
    fun `without a file name, the format stands in`() {
        assertEquals("Chapter 1.cbz", archive(path = "").label(showExtension = true))
    }

    @Test
    fun `folders have no extension`() {
        val folder = archive(path = "Series", format = "folder", title = "Series").copy(mediaType = "folder")
        assertEquals("Series", folder.label(showExtension = true))
    }

    @Test
    fun `a name that already ends with it isn't given it twice`() {
        assertEquals("Issue 3.cbz", withExtension("Issue 3.cbz", "cbz", show = true))
        assertEquals("Issue 3.cbz", withExtension("Issue 3", "cbz", show = true))
        assertEquals("Issue 3", withExtension("Issue 3", "cbz", show = false))
    }
}
