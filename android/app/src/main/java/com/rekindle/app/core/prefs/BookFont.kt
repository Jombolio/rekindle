package com.rekindle.app.core.prefs

/**
 * The typefaces offered for reading. [ORIGINAL] keeps whatever the book asks for,
 * including fonts embedded in it. The others use the device's own fonts, so
 * choosing one downloads nothing and adds nothing to the app.
 */
enum class BookFont(val label: String, val cssFamily: String?) {
    ORIGINAL("Book's own", null),
    SERIF("Serif", "serif"),
    SANS("Sans-serif", "sans-serif"),
    MONO("Monospace", "monospace");

    val next: BookFont get() = entries[(ordinal + 1) % entries.size]

    /** CSS that overrides the book's fonts, or nothing when the book's are kept. */
    val css: String get() = cssFamily?.let { "body, body * { font-family: $it !important; }" }.orEmpty()

    companion object {
        /** Prefs store the name, so an unknown value from another version is harmless. */
        fun parse(name: String?): BookFont = entries.firstOrNull { it.name == name } ?: ORIGINAL
    }
}

const val DEFAULT_BOOK_FONT_SIZE = 16f
const val MIN_BOOK_FONT_SIZE = 10f
const val MAX_BOOK_FONT_SIZE = 32f
