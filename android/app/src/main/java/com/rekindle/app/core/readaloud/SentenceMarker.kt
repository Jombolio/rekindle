package com.rekindle.app.core.readaloud

import org.jsoup.nodes.Element
import org.jsoup.nodes.Node
import org.jsoup.nodes.TextNode
import org.jsoup.parser.ParseSettings
import org.jsoup.parser.Parser

/**
 * A chapter's body with every sentence marked, and the sentences to speak.
 *
 * [html] has each run of a sentence's text in a `<span data-ra="n">`. A sentence
 * crossing an inline element, such as an italicised phrase, is several spans with
 * the same number. The spans carry no style, so the chapter lays out as before.
 * The page shows this HTML and the speech reads [sentences], so a sentence's number
 * is the same in both.
 */
class MarkedChapter(
    val html: String,
    /** The sentences in reading order, as plain text. A sentence's number is its index. */
    val sentences: List<String>,
    /** How far through the chapter's text each sentence starts, from 0 to 1. */
    val starts: List<Float>,
) {
    /** Whether sentence [i] has anything to say: a row of asterisks marking a scene
     *  break is a sentence on the page, but nothing to read aloud. */
    fun speakable(i: Int): Boolean = SPEAKABLE.containsMatchIn(sentences[i])

    /** The sentence that [fraction] of the way through the chapter falls within. */
    fun sentenceAt(fraction: Float): Int {
        var found = 0
        for (i in starts.indices) if (starts[i] <= fraction + 1e-6f) found = i
        return found
    }

    private companion object {
        val SPEAKABLE = Regex("[\\p{L}\\p{N}]")
    }
}

/**
 * Splits a chapter into sentences for reading aloud. A port of the desktop client's
 * `markSentences` (desktop/lib/core/read_aloud/sentences.dart), with the same rules.
 */
object SentenceMarker {

    /** The attribute that ties each piece of the page's text to its sentence. */
    const val ATTRIBUTE = "data-ra"

    /** Elements that end whatever sentence is open: a heading or a paragraph is never
     *  read as part of the one before it, punctuated or not. */
    private val BLOCKS = setOf(
        "address", "article", "aside", "blockquote", "br", "dd", "div", "dl", "dt",
        "figcaption", "figure", "footer", "h1", "h2", "h3", "h4", "h5", "h6",
        "header", "hr", "li", "nav", "ol", "p", "pre", "section", "table", "td",
        "th", "tr", "ul",
    )

    /** Elements whose text is not read: code and styling, ruby annotations, pictures. */
    private val SILENT = setOf("script", "style", "rt", "rp", "svg", "math", "head", "title")

    /** Words that end in a full stop without ending the sentence. */
    private val ABBREVIATION = Regex(
        "(?U)(?:^|[\\s(“\"‘])(?:Mr|Mrs|Ms|Mx|Dr|Prof|St|Jr|Sr|Mt|No|vs|etc|viz|cf|" +
            "Gen|Col|Capt|Lt|Sgt|Rev|Hon|Fr|[A-HJ-Z])\\.$",
    )

    /** The end of a sentence: closing punctuation, any closing quotes or brackets,
     *  then space or the end of the text. */
    private val END = Regex("(?U)[.!?…]+[\"'”’)\\]]*(?=\\s|$)")
    private val STRONG_END = Regex("[!?…]")
    private val SPACES = Regex("(?U)\\s+")

    /** Marks the sentences of a chapter's body HTML. See [MarkedChapter]. */
    fun mark(bodyHtml: String): MarkedChapter {
        // Case is kept as written: SVG attributes such as viewBox depend on it.
        val parser = Parser.htmlParser().settings(ParseSettings.preserveCase)
        val document = parser.parseInput("<body>$bodyHtml</body>", "")
        document.outputSettings().prettyPrint(false)
        val body = document.body()

        val sentences = mutableListOf<String>()
        val offsets = mutableListOf<Int>()
        val open = StringBuilder()
        var text = 0

        fun close() {
            val sentence = open.toString().replace(SPACES, " ").trim()
            open.setLength(0)
            if (sentence.isNotEmpty()) sentences += sentence
        }

        fun startIfNew() {
            if (open.isBlank() && offsets.size == sentences.size) offsets += text
        }

        fun markText(node: TextNode) {
            val value = node.wholeText
            val pieces = mutableListOf<Node>()
            var at = 0

            fun emit(piece: String, ends: Boolean) {
                if (piece.isEmpty()) return
                if (piece.isBlank()) {
                    pieces += TextNode(piece)
                    open.append(piece)
                    text += piece.length
                    return
                }
                startIfNew()
                pieces += Element("span").attr(ATTRIBUTE, sentences.size.toString())
                    .appendChild(TextNode(piece))
                open.append(piece)
                text += piece.length
                if (ends) close()
            }

            for (m in END.findAll(value)) {
                val upTo = value.substring(at, m.range.last + 1)
                // "Mr." and an initial end in a full stop but carry on the sentence.
                val before = "$open$upTo".trimEnd()
                if (m.value.startsWith('.') && !STRONG_END.containsMatchIn(m.value) &&
                    ABBREVIATION.containsMatchIn(before)
                ) {
                    continue
                }
                emit(upTo, ends = true)
                at = m.range.last + 1
            }
            emit(value.substring(at), ends = false)

            for (piece in pieces) node.before(piece)
            node.remove()
        }

        fun walk(node: Node) {
            when (node) {
                is TextNode -> markText(node)
                is Element -> {
                    val tag = node.normalName()
                    if (tag in SILENT) return
                    val block = tag in BLOCKS
                    if (block) close()
                    for (child in node.childNodes().toList()) walk(child)
                    if (block) close()
                }
                // Comments and the like hold nothing to read.
                else -> {}
            }
        }

        for (child in body.childNodes().toList()) walk(child)
        close()

        val total = if (text == 0) 1 else text
        return MarkedChapter(
            html = body.html(),
            sentences = sentences,
            starts = offsets.take(sentences.size).map { it.toFloat() / total },
        )
    }
}
