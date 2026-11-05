package com.rekindle.app.core.dictionary

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileNotFoundException
import java.io.InputStream
import java.util.zip.GZIPInputStream
import javax.inject.Inject
import javax.inject.Singleton

data class DictionarySense(val definition: String, val example: String?)

/** One headword as one part of speech, with its most common meanings first. */
data class DictionaryEntry(val word: String, val partOfSpeech: String, val senses: List<DictionarySense>)

/**
 * Works out which dictionary headwords a selection might be, so "running", "mice" and
 * "Dogs," all find their entries. Follows WordNet's own rules for undoing inflections;
 * irregular forms come from its exception table.
 *
 * Desktop has the same rules in `word_forms.dart`. Keep the two in step.
 */
object WordForms {
    private const val MAX_WORDS = 4
    private const val MAX_LENGTH = 60

    private val RULES = listOf(
        // Nouns
        "s" to "", "ses" to "s", "xes" to "x", "zes" to "z", "ches" to "ch",
        "shes" to "sh", "men" to "man", "ies" to "y",
        // Verbs
        "es" to "e", "es" to "", "ed" to "e", "ed" to "", "ing" to "e", "ing" to "",
        // Adjectives
        "er" to "", "est" to "", "er" to "e", "est" to "e",
    )

    /** The selection as a dictionary would list it, or null if it can't be a word or
     *  short phrase, such as a whole sentence. */
    fun normalize(selection: String): String? {
        val text = selection
            .replace(Regex("[‘’ʼ]"), "'")
            .replace(Regex("\\s+"), " ")
            .trim()
            .lowercase()
            .replace(Regex("^[^\\p{L}\\p{N}]+"), "")
            .replace(Regex("[^\\p{L}\\p{N}]+$"), "")
            .removeSuffix("'s")
        if (text.isEmpty() || text.length > MAX_LENGTH) return null
        if (text.split(' ').size > MAX_WORDS) return null
        return text
    }

    /** Possible headwords for a normalized word, most likely first. */
    fun stems(word: String): List<String> {
        val found = linkedSetOf(word)
        for ((suffix, replacement) in RULES) {
            if (word.length > suffix.length && word.endsWith(suffix)) {
                found += word.dropLast(suffix.length) + replacement
            }
        }
        return found.toList()
    }
}

/**
 * The built-in English dictionary, from WordNet (see tools/build_wordnet.py). Unpacked
 * on first use, so it costs nothing unless the reader looks a word up.
 */
@Singleton
class WordNetDictionary @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    private val openLock = Mutex()
    private var database: SQLiteDatabase? = null

    /** Entries for a selection, or an empty list if it isn't in the dictionary. */
    suspend fun lookup(selection: String): List<DictionaryEntry> = withContext(Dispatchers.IO) {
        val word = WordForms.normalize(selection) ?: return@withContext emptyList()
        val db = open()

        val candidates = linkedSetOf(word)
        candidates += irregularForms(db, word)
        candidates += WordForms.stems(word)

        val entries = mutableListOf<DictionaryEntry>()
        for (candidate in candidates) {
            entries += entriesFor(db, candidate)
            if (entries.map { it.word }.distinct().size >= MAX_WORDS_SHOWN) break
        }
        entries
    }

    private suspend fun open(): SQLiteDatabase = openLock.withLock {
        database ?: run {
            // Not backed up: it can always be unpacked again.
            val file = File(context.noBackupFilesDir, "wordnet-$VERSION.db")
            if (!file.exists()) {
                // Moved into place once complete, so a crash can't leave half a database.
                val temp = File(file.path + ".tmp")
                openAsset().use { input -> temp.outputStream().use { input.copyTo(it) } }
                check(temp.renameTo(file)) { "Couldn't unpack the dictionary." }
            }
            SQLiteDatabase.openDatabase(file.path, null, SQLiteDatabase.OPEN_READONLY).also { database = it }
        }
    }

    /**
     * The Android build unpacks .gz assets and drops the suffix, compressing them in
     * the APK instead. Falls back to the packed name in case a build ever doesn't.
     */
    private fun openAsset(): InputStream = try {
        context.assets.open("wordnet.db")
    } catch (_: FileNotFoundException) {
        GZIPInputStream(context.assets.open("wordnet.db.gz"))
    }

    private fun irregularForms(db: SQLiteDatabase, form: String): List<String> =
        db.rawQuery("SELECT lemma FROM exceptions WHERE form = ?", arrayOf(form)).use { cursor ->
            buildList { while (cursor.moveToNext()) add(cursor.getString(0)) }
        }

    private fun entriesFor(db: SQLiteDatabase, word: String): List<DictionaryEntry> {
        val byPos = mutableMapOf<String, MutableList<DictionarySense>>()
        db.rawQuery(
            "SELECT s.pos, y.definition, y.example FROM senses s " +
                "JOIN synsets y ON y.id = s.synset WHERE s.word = ? ORDER BY s.sense",
            arrayOf(word),
        ).use { cursor ->
            while (cursor.moveToNext()) {
                val senses = byPos.getOrPut(cursor.getString(0)) { mutableListOf() }
                if (senses.size < MAX_SENSES_PER_ENTRY) {
                    senses += DictionarySense(
                        cursor.getString(1),
                        if (cursor.isNull(2)) null else cursor.getString(2),
                    )
                }
            }
        }
        return PARTS_OF_SPEECH.mapNotNull { (pos, name) ->
            byPos[pos]?.let { DictionaryEntry(word, name, it) }
        }
    }

    private companion object {
        /** Bump with the database, so an app update replaces the unpacked copy. */
        const val VERSION = 1
        const val MAX_WORDS_SHOWN = 2
        const val MAX_SENSES_PER_ENTRY = 3
        val PARTS_OF_SPEECH = listOf("n" to "noun", "v" to "verb", "a" to "adjective", "r" to "adverb")
    }
}
