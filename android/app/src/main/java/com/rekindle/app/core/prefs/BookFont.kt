package com.rekindle.app.core.prefs

/**
 * The typefaces offered for reading. [ORIGINAL] keeps whatever the book asks for,
 * including fonts embedded in it. Serif, sans-serif and monospace use the device's
 * own fonts. The last three are bundled for readability, under the SIL Open Font
 * License: OpenDyslexic for dyslexia, Atkinson Hyperlegible for low vision, and
 * Lexend for reading fluency.
 */
enum class BookFont(val label: String, val cssFamily: String?) {
    ORIGINAL("Book's own", null),
    SERIF("Serif", "serif"),
    SANS("Sans-serif", "sans-serif"),
    MONO("Monospace", "monospace"),
    OPEN_DYSLEXIC("OpenDyslexic", "'OpenDyslexic', sans-serif"),
    ATKINSON("Atkinson Hyperlegible", "'Atkinson Hyperlegible', sans-serif"),
    LEXEND("Lexend", "'Lexend', sans-serif");

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

/** Where the reader serves the bundled fonts from, inside the book's private host. */
const val BUNDLED_FONT_PATH = "__rekindle__/fonts/"

/** The bundled fonts' files, in the app's assets under `fonts/`. */
val BUNDLED_FONT_FILES = setOf(
    "OpenDyslexic-Regular.otf", "OpenDyslexic-Bold.otf", "OpenDyslexic-Italic.otf", "OpenDyslexic-BoldItalic.otf",
    "AtkinsonHyperlegible-Regular.ttf", "AtkinsonHyperlegible-Bold.ttf",
    "AtkinsonHyperlegible-Italic.ttf", "AtkinsonHyperlegible-BoldItalic.ttf",
    "Lexend-Variable.ttf",
)

/** The bundled fonts' licences, shown under Settings → Licences. */
val BUNDLED_FONT_LICENCES = listOf(
    "OpenDyslexic" to "fonts/OFL-OpenDyslexic.txt",
    "Atkinson Hyperlegible" to "fonts/OFL-AtkinsonHyperlegible.txt",
    "Lexend" to "fonts/OFL-Lexend.txt",
)

/**
 * @font-face rules for the bundled fonts. A browser only fetches a font once text
 * uses it, so declaring all of them costs nothing until one is chosen.
 */
val BUNDLED_FONT_FACES: String = buildString {
    fun face(family: String, file: String, weight: String, style: String) {
        append("@font-face{font-family:'").append(family).append("';src:url('/")
            .append(BUNDLED_FONT_PATH).append(file).append("');font-weight:").append(weight)
            .append(";font-style:").append(style).append(";}")
    }
    for ((family, prefix) in listOf("OpenDyslexic" to "OpenDyslexic", "Atkinson Hyperlegible" to "AtkinsonHyperlegible")) {
        val ext = if (prefix == "OpenDyslexic") "otf" else "ttf"
        face(family, "$prefix-Regular.$ext", "400", "normal")
        face(family, "$prefix-Bold.$ext", "700", "normal")
        face(family, "$prefix-Italic.$ext", "400", "italic")
        face(family, "$prefix-BoldItalic.$ext", "700", "italic")
    }
    face("Lexend", "Lexend-Variable.ttf", "100 900", "normal")
}
