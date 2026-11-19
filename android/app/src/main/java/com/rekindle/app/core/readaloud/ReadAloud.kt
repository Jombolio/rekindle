package com.rekindle.app.core.readaloud

import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.speech.tts.Voice
import androidx.core.content.ContextCompat
import com.rekindle.app.core.prefs.PrefsStore
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.Locale
import javax.inject.Inject
import javax.inject.Singleton

/** A voice the phone's text-to-speech engine offers, installed for use offline. */
data class ReadAloudVoice(val name: String, val label: String, val locale: Locale)

/**
 * Reads books aloud with the phone's own text-to-speech engine, a sentence at a
 * time, moving on through the chapters by itself. Lives for the app rather than a
 * screen, so [ReadAloudService] can keep it going with the screen off and answer
 * the notification's buttons; the reader starts and stops it.
 *
 * Everything here runs on the main thread. The engine reports from its own, so its
 * callbacks are posted back. Each start bumps [token], which every queued sentence
 * carries in its utterance id, so callbacks from speech that was cut off are ignored.
 */
@Singleton
class ReadAloud @Inject constructor(
    @ApplicationContext private val context: Context,
    prefs: PrefsStore,
) {
    enum class Status { IDLE, STARTING, PLAYING, PAUSED }

    data class State(
        val status: Status = Status.IDLE,
        /** The chapter being read, or -1. */
        val chapter: Int = -1,
        /** The sentence being read, in the chapter's [MarkedChapter] numbering. */
        val sentence: Int? = null,
    ) {
        val active: Boolean get() = status != Status.IDLE
    }

    /** What is being read: its chapters, and how to get each one's sentences. */
    interface Book {
        val title: String
        val chapterCount: Int
        fun chapterTitle(index: Int): String

        /** The chapter's sentences, or null if it can't be read. Called off the main thread. */
        fun sentences(chapter: Int): MarkedChapter?
    }

    private val _state = MutableStateFlow(State())
    val state = _state.asStateFlow()

    private val _errors = MutableSharedFlow<String>(extraBufferCapacity = 4)

    /** Problems to tell the reader about, such as there being no engine. */
    val errors = _errors.asSharedFlow()

    /** The book being read, while one is. */
    var book: Book? = null
        private set

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val main = Handler(Looper.getMainLooper())

    private var engine: TextToSpeech? = null
    private var engineReady: CompletableDeferred<Boolean>? = null

    private var marked: MarkedChapter? = null
    private var token = 0
    private var queuedUpTo = -1
    private var voiceName = ""
    private var rate = 1f

    init {
        scope.launch {
            combine(prefs.readAloudVoice, prefs.readAloudRate) { voice, rate -> voice to rate }
                .collect { (voice, newRate) ->
                    val changed = voice != voiceName || newRate != rate
                    voiceName = voice
                    rate = newRate
                    // The sentence being read starts again in the new voice.
                    if (changed && _state.value.status == Status.PLAYING) restart()
                }
        }
    }

    /** Reads [book] aloud from sentence [sentence] of chapter [chapter]. */
    fun read(book: Book, chapter: Int, sentence: Int) {
        val mine = ++token
        engine?.stop()
        // The chapter already being read needn't be split again.
        val known = marked.takeIf { book === this.book && chapter == loadedChapter }
        // Set before the state, which the reader checks against its book.
        this.book = book
        _state.value = State(Status.STARTING, chapter, null)
        ContextCompat.startForegroundService(context, Intent(context, ReadAloudService::class.java))
        scope.launch {
            val tts = engine()
            if (mine != token) return@launch
            if (tts == null) {
                _errors.tryEmit(
                    "No text-to-speech voice is available. Add one in your phone's settings, " +
                        "under text-to-speech output.",
                )
                stop()
                return@launch
            }
            val chapterSentences = known ?: load(book, chapter)
            if (mine != token) return@launch
            if (chapterSentences == null) {
                _errors.tryEmit("This chapter couldn't be read aloud.")
                stop()
                return@launch
            }
            marked = chapterSentences
            loadedChapter = chapter
            applyVoice(tts)
            speakFrom(sentence)
        }
    }

    /** The chapter [marked] holds. */
    private var loadedChapter = -1

    private suspend fun load(book: Book, chapter: Int): MarkedChapter? =
        withContext(Dispatchers.IO) { runCatching { book.sentences(chapter) }.getOrNull() }

    fun pause() {
        if (_state.value.status != Status.PLAYING) return
        token++
        engine?.stop()
        _state.value = _state.value.copy(status = Status.PAUSED)
    }

    fun resume() {
        if (_state.value.status != Status.PAUSED) return
        restart()
    }

    fun togglePause() = if (_state.value.status == Status.PLAYING) pause() else resume()

    /** How far through the chapter being read [sentence] starts, from 0 to 1. */
    fun fractionOf(sentence: Int): Float? = marked?.starts?.getOrNull(sentence)

    fun stop() {
        token++
        engine?.stop()
        marked = null
        loadedChapter = -1
        book = null
        _state.value = State()
    }

    /** Stops, and lets go of the engine. */
    fun release() {
        stop()
        engine?.shutdown()
        engine = null
        engineReady = null
    }

    /** The installed voices, the phone's own language first. Empty if there's no engine. */
    suspend fun voices(): List<ReadAloudVoice> {
        val tts = engine() ?: return emptyList()
        val language = Locale.getDefault().language
        return runCatching { tts.voices.orEmpty() }.getOrDefault(emptySet())
            .filter { !it.isNetworkConnectionRequired && TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED !in it.features.orEmpty() }
            .map { ReadAloudVoice(it.name, it.locale.displayName, it.locale) }
            .sortedWith(compareBy<ReadAloudVoice>({ it.locale.language != language }, { it.label }, { it.name }))
    }

    /** Says [text] in the chosen voice and speed, to try them. Not while reading. */
    fun preview(text: String) {
        if (_state.value.active) return
        scope.launch {
            val tts = engine() ?: run {
                _errors.tryEmit("No text-to-speech voice is available.")
                return@launch
            }
            if (_state.value.active) return@launch
            applyVoice(tts)
            // Its id carries no token, so the progress callbacks ignore it.
            tts.speak(text, TextToSpeech.QUEUE_FLUSH, null, "preview")
        }
    }

    /** Lets go of the engine if nothing is being read, for screens that only list voices. */
    fun releaseIfIdle() {
        if (!_state.value.active) release()
    }

    // ── Speaking ─────────────────────────────────────────────────────────────

    private fun restart() {
        val tts = engine ?: return
        val sentence = _state.value.sentence ?: 0
        token++
        tts.stop()
        applyVoice(tts)
        speakFrom(sentence)
    }

    private fun speakFrom(sentence: Int) {
        val chapter = marked ?: return
        var first = sentence.coerceAtLeast(0)
        while (first < chapter.sentences.size && !chapter.speakable(first)) first++
        if (first >= chapter.sentences.size) {
            chapterEnded()
            return
        }
        _state.value = State(Status.PLAYING, loadedChapter, first)
        queuedUpTo = first - 1
        queueTo(first + WINDOW)
    }

    /**
     * Queues sentences up to [last]. A few at a time rather than the whole chapter,
     * so a change of voice or speed has little to throw away. The chapter's end is
     * a moment of silence whose finishing moves on to the next.
     */
    private fun queueTo(last: Int) {
        val chapter = marked ?: return
        val tts = engine ?: return
        val end = chapter.sentences.size - 1
        while (queuedUpTo < minOf(last, end)) {
            queuedUpTo++
            val i = queuedUpTo
            if (!chapter.speakable(i)) continue
            val parts = split(chapter.sentences[i], maxInput())
            parts.forEachIndexed { part, text ->
                tts.speak(text, TextToSpeech.QUEUE_ADD, null, "$token:$i:$part")
            }
            if (i == end) tts.playSilentUtterance(CHAPTER_PAUSE_MS, TextToSpeech.QUEUE_ADD, "$token:$END")
        }
    }

    private fun chapterEnded() {
        val book = book ?: return stop()
        val next = loadedChapter + 1
        if (next >= book.chapterCount) {
            stop()
            return
        }
        val mine = ++token
        _state.value = State(Status.PLAYING, next, null)
        scope.launch {
            val chapter = load(book, next)
            if (mine != token) return@launch
            if (chapter == null) {
                _errors.tryEmit("The next chapter couldn't be read aloud.")
                stop()
                return@launch
            }
            marked = chapter
            loadedChapter = next
            speakFrom(0)
        }
    }

    private val progress = object : UtteranceProgressListener() {
        override fun onStart(utteranceId: String) {
            main.post { started(utteranceId) }
        }

        override fun onDone(utteranceId: String) {
            main.post { finished(utteranceId) }
        }

        @Deprecated("Deprecated in Java")
        override fun onError(utteranceId: String) = onError(utteranceId, TextToSpeech.ERROR)

        override fun onError(utteranceId: String, errorCode: Int) {
            main.post {
                if (tokenOf(utteranceId) != token) return@post
                _errors.tryEmit("Reading aloud stopped: the text-to-speech engine failed.")
                stop()
            }
        }
    }

    private fun tokenOf(id: String) = id.substringBefore(':').toIntOrNull()

    private fun started(id: String) {
        if (tokenOf(id) != token) return
        val parts = id.split(':')
        val sentence = parts.getOrNull(1)?.toIntOrNull() ?: return
        if (parts.getOrNull(2) != "0") return
        if (_state.value.status != Status.PLAYING) return
        _state.value = _state.value.copy(sentence = sentence)
        queueTo(sentence + WINDOW)
    }

    private fun finished(id: String) {
        if (tokenOf(id) != token) return
        if (id.substringAfter(':') == END) chapterEnded()
    }

    // ── The engine ───────────────────────────────────────────────────────────

    private suspend fun engine(): TextToSpeech? {
        engineReady?.let { ready ->
            return if (ready.await()) engine else null
        }
        val ready = CompletableDeferred<Boolean>()
        engineReady = ready
        val tts = TextToSpeech(context) { status -> ready.complete(status == TextToSpeech.SUCCESS) }
        engine = tts
        if (!ready.await()) {
            tts.shutdown()
            if (engine === tts) {
                engine = null
                engineReady = null
            }
            return null
        }
        tts.setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build(),
        )
        tts.setOnUtteranceProgressListener(progress)
        return tts
    }

    private fun applyVoice(tts: TextToSpeech) {
        val voice: Voice? = if (voiceName.isBlank()) null
        else runCatching { tts.voices?.firstOrNull { it.name == voiceName } }.getOrNull()
        runCatching { tts.voice = voice ?: tts.defaultVoice }
        tts.setSpeechRate(rate)
    }

    private fun maxInput() =
        runCatching { TextToSpeech.getMaxSpeechInputLength() }.getOrDefault(4000).coerceAtLeast(200)

    companion object {
        /** How many sentences are queued ahead of the one being read. */
        private const val WINDOW = 4
        private const val CHAPTER_PAUSE_MS = 600L
        private const val END = "end"

        /** Splits text longer than the engine takes at once, between words where it can. */
        internal fun split(text: String, max: Int): List<String> {
            if (text.length <= max) return listOf(text)
            val parts = mutableListOf<String>()
            var rest = text
            while (rest.length > max) {
                val cut = rest.lastIndexOf(' ', max).takeIf { it > max / 2 } ?: max
                parts += rest.substring(0, cut).trim()
                rest = rest.substring(cut).trim()
            }
            if (rest.isNotEmpty()) parts += rest
            return parts
        }
    }
}
