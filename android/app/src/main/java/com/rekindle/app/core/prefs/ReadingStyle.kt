package com.rekindle.app.core.prefs

import com.google.gson.Gson
import com.google.gson.JsonObject
import com.google.gson.JsonParser

/** How a book is laid out for reading. */
enum class BookLayout(val label: String) {
    SCROLL("Scroll by chapter"),
    CONTINUOUS("Continuous scroll"),
    PAGE("Single page"),
    SPREAD("Two pages");

    val paged: Boolean get() = this == PAGE || this == SPREAD

    companion object {
        fun parse(name: String?): BookLayout = entries.firstOrNull { it.name == name } ?: SCROLL
    }
}

/** How paragraphs are aligned. [BOOK] keeps whatever the book asks for. */
enum class BookAlign(val label: String) {
    BOOK("Book's own"),
    LEFT("Left"),
    JUSTIFY("Justified");

    companion object {
        fun parse(name: String?): BookAlign = entries.firstOrNull { it.name == name } ?: BOOK
    }
}

/**
 * The layout and readability options for books, besides the font, its size and the
 * theme, which have settings of their own. Values are clamped to their ranges, so a
 * preference from another version can't break the reader.
 */
data class ReadingStyle(
    val layout: BookLayout = BookLayout.SCROLL,
    /** Line height, as a multiple of the font size. */
    val lineHeight: Float = 1.6f,
    /** Extra space between letters and between words, in ems. */
    val letterSpacing: Float = 0f,
    val wordSpacing: Float = 0f,
    /** Space after each paragraph, in ems. 0 leaves the book's own spacing. */
    val paragraphSpacing: Float = 0f,
    /** The widest a line gets, in ems of the reading font. */
    val measure: Float = 36f,
    val align: BookAlign = BookAlign.BOOK,
    /** Sets all text in bold. */
    val bold: Boolean = false,
    /** Animates page turns. Off, pages change at once. */
    val animations: Boolean = true,
    /** A band around the line being read, with the rest of the page dimmed. */
    val ruler: Boolean = false,
) {
    /** The same style with every value inside its range. */
    fun clamped(): ReadingStyle = copy(
        lineHeight = lineHeight.inRange(LINE_HEIGHT),
        letterSpacing = letterSpacing.inRange(LETTER_SPACING),
        wordSpacing = wordSpacing.inRange(WORD_SPACING),
        paragraphSpacing = paragraphSpacing.inRange(PARAGRAPH_SPACING),
        measure = measure.inRange(MEASURE),
    )

    fun toJson(): String = Gson().toJson(
        JsonObject().apply {
            addProperty("layout", layout.name)
            addProperty("lineHeight", lineHeight)
            addProperty("letterSpacing", letterSpacing)
            addProperty("wordSpacing", wordSpacing)
            addProperty("paragraphSpacing", paragraphSpacing)
            addProperty("measure", measure)
            addProperty("align", align.name)
            addProperty("bold", bold)
            addProperty("animations", animations)
            addProperty("ruler", ruler)
        },
    )

    companion object {
        val LINE_HEIGHT = 1.2f..2.4f
        val LETTER_SPACING = 0f..0.2f
        val WORD_SPACING = 0f..0.6f
        val PARAGRAPH_SPACING = 0f..2f
        val MEASURE = 24f..60f

        private fun Float.inRange(range: ClosedFloatingPointRange<Float>) =
            if (isFinite()) coerceIn(range) else range.start

        /** Anything missing or unreadable takes its default. */
        fun fromJson(json: String?): ReadingStyle {
            val d = ReadingStyle()
            val o = runCatching { JsonParser.parseString(json.orEmpty()).asJsonObject }.getOrNull()
                ?: return d
            fun num(key: String, default: Float) =
                runCatching { o.get(key)?.asFloat }.getOrNull() ?: default
            fun flag(key: String, default: Boolean) =
                runCatching { o.get(key)?.takeIf { it.isJsonPrimitive && it.asJsonPrimitive.isBoolean }?.asBoolean }
                    .getOrNull() ?: default
            fun text(key: String) = runCatching { o.get(key)?.asString }.getOrNull()
            return ReadingStyle(
                layout = BookLayout.parse(text("layout")),
                lineHeight = num("lineHeight", d.lineHeight),
                letterSpacing = num("letterSpacing", d.letterSpacing),
                wordSpacing = num("wordSpacing", d.wordSpacing),
                paragraphSpacing = num("paragraphSpacing", d.paragraphSpacing),
                measure = num("measure", d.measure),
                align = BookAlign.parse(text("align")),
                bold = flag("bold", d.bold),
                animations = flag("animations", d.animations),
                ruler = flag("ruler", d.ruler),
            ).clamped()
        }
    }
}

/**
 * The reader's CSS for a [ReadingStyle], laid over the book's own. Spacing and bold
 * text override the book, since that's the point of choosing them. Alignment is
 * applied at a specificity that a book's own classes beat, so text it deliberately
 * centres, such as title pages, stays centred.
 */
object ReadingCss {

    /** Room kept clear for the reader's bars, in CSS pixels. */
    const val TOP_INSET = 56
    const val BOTTOM_INSET = 64

    fun css(style: ReadingStyle): String = buildString {
        append(BUNDLED_FONT_FACES)
        append("body{line-height:").append(style.lineHeight).append(" !important;}")
        append("body *{line-height:inherit !important;}")
        if (style.letterSpacing > 0f) {
            append("body,body *{letter-spacing:").append(style.letterSpacing).append("em !important;}")
        }
        if (style.wordSpacing > 0f) {
            append("body,body *{word-spacing:").append(style.wordSpacing).append("em !important;}")
        }
        if (style.paragraphSpacing > 0f) {
            append("body p{margin-bottom:").append(style.paragraphSpacing).append("em !important;}")
        }
        when (style.align) {
            BookAlign.BOOK -> {}
            BookAlign.LEFT -> append("html body p,html body li,html body blockquote,html body dd{text-align:left;}")
            BookAlign.JUSTIFY -> append(
                "html body p,html body li,html body blockquote,html body dd{text-align:justify;hyphens:auto;}",
            )
        }
        if (style.bold) append("body,body *{font-weight:700 !important;}")
        append(layoutCss(style))
    }

    private fun layoutCss(style: ReadingStyle): String {
        val measure = "${style.measure}em"
        return when (style.layout) {
            BookLayout.SCROLL, BookLayout.CONTINUOUS ->
                "body{max-width:$measure !important;margin:0 auto !important;" +
                    "padding:${TOP_INSET + 8}px 16px ${BOTTOM_INSET + 16}px !important;box-sizing:border-box;}" +
                    // Chapters added above the reading spot mustn't shift the page.
                    (if (style.layout == BookLayout.CONTINUOUS) "html,body{overflow-anchor:none;}" else "")

            // Pages are columns of the document, each exactly one screen (or half of
            // one) apart, so turning a page is scrolling sideways by that much.
            BookLayout.PAGE, BookLayout.SPREAD -> {
                val period = if (style.layout == BookLayout.SPREAD) "50vw" else "100vw"
                val column = "min($measure,calc($period - 32px))"
                val gap = "calc($period - $column)"
                "html{height:100%;overflow:hidden !important;}" +
                    "body{height:100vh !important;max-width:none !important;margin:0 !important;" +
                    "box-sizing:border-box;padding:${TOP_INSET}px calc(($period - $column) / 2) ${BOTTOM_INSET}px !important;" +
                    "column-width:$column;column-gap:$gap;column-fill:auto;}" +
                    "img,svg,figure,table{max-height:calc(100vh - ${TOP_INSET + BOTTOM_INSET + 16}px);" +
                    "break-inside:avoid;object-fit:contain;}" +
                    // Like a printed book, a chapter opens on a right-hand page:
                    // an empty first column takes the left.
                    (if (style.layout == BookLayout.SPREAD) "body::before{content:'';display:block;break-after:column;}" else "")
            }
        }
    }
}
