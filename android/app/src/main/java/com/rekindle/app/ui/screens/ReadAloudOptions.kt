package com.rekindle.app.ui.screens

import android.content.ActivityNotFoundException
import android.content.Intent
import android.provider.Settings
import android.widget.Toast
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.rekindle.app.core.prefs.MAX_READ_ALOUD_RATE
import com.rekindle.app.core.prefs.MIN_READ_ALOUD_RATE
import com.rekindle.app.core.prefs.PrefsStore
import com.rekindle.app.core.readaloud.ReadAloud
import com.rekindle.app.core.readaloud.ReadAloudVoice
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject
import kotlin.math.roundToInt

/** A voice as listed: engines name voices for machines, so they're numbered by language. */
data class VoiceChoice(val name: String, val label: String)

@HiltViewModel
class ReadAloudOptionsViewModel @Inject constructor(
    private val readAloud: ReadAloud,
    private val prefs: PrefsStore,
) : ViewModel() {

    /** The installed voices; null while finding out. */
    val voices = MutableStateFlow<List<VoiceChoice>?>(null)
    val voice = prefs.readAloudVoice.stateIn(viewModelScope, SharingStarted.Eagerly, "")
    val rate = prefs.readAloudRate.stateIn(viewModelScope, SharingStarted.Eagerly, 1f)

    init {
        viewModelScope.launch { voices.value = label(readAloud.voices()) }
    }

    private fun label(voices: List<ReadAloudVoice>): List<VoiceChoice> {
        val perLanguage = voices.groupingBy { it.label }.eachCount()
        val seen = mutableMapOf<String, Int>()
        return voices.map { v ->
            val n = seen.merge(v.label, 1, Int::plus)!!
            VoiceChoice(v.name, if ((perLanguage[v.label] ?: 0) > 1) "${v.label} · voice $n" else v.label)
        }
    }

    fun setVoice(name: String) {
        viewModelScope.launch {
            prefs.setReadAloudVoice(name)
            readAloud.preview(SAMPLE)
        }
    }

    fun setRate(rate: Float) {
        viewModelScope.launch { prefs.setReadAloudRate(rate) }
    }

    fun preview() = readAloud.preview(SAMPLE)

    override fun onCleared() {
        readAloud.releaseIfIdle()
    }

    private companion object {
        const val SAMPLE = "This is how your books will sound when they're read aloud."
    }
}

/**
 * The voice and speed books are read aloud in. Voices are the phone's own
 * text-to-speech engine's; more can be added in the phone's settings.
 */
@Composable
fun ReadAloudOptions(vm: ReadAloudOptionsViewModel = hiltViewModel()) {
    val voices by vm.voices.collectAsState()
    val voice by vm.voice.collectAsState()
    val rate by vm.rate.collectAsState()
    val context = LocalContext.current
    var open by remember { mutableStateOf(false) }
    // Saved when let go: each change restarts the sentence being read.
    var dragging by remember { mutableStateOf<Float?>(null) }
    val shownRate = dragging ?: rate

    Column {
        val current = voices?.firstOrNull { it.name == voice }?.label ?: "Phone's default"
        Text("Voice", style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 4.dp))
        Box {
            OutlinedButton(
                onClick = { open = true },
                enabled = voices != null,
                modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
            ) {
                Text(
                    if (voices == null) "Finding voices…" else current,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                Icon(Icons.Default.ArrowDropDown, null)
            }
            DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
                DropdownMenuItem(text = { Text("Phone's default") }, onClick = { open = false; vm.setVoice("") })
                voices.orEmpty().forEach { choice ->
                    DropdownMenuItem(text = { Text(choice.label) }, onClick = { open = false; vm.setVoice(choice.name) })
                }
            }
        }
        if (voices?.isEmpty() == true) {
            Text(
                "No voices are installed for use offline. Add one in your phone's text-to-speech settings.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 4.dp),
            )
        }

        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 12.dp)) {
            Text("Speed", style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
            Text("%.1f×".format(shownRate), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary)
        }
        Slider(
            value = shownRate,
            onValueChange = { dragging = (it * 10).roundToInt() / 10f },
            onValueChangeFinished = {
                dragging?.let(vm::setRate)
                dragging = null
            },
            valueRange = MIN_READ_ALOUD_RATE..MAX_READ_ALOUD_RATE,
            steps = ((MAX_READ_ALOUD_RATE - MIN_READ_ALOUD_RATE) * 10).roundToInt() - 1,
        )

        Row {
            TextButton(onClick = vm::preview) { Text("Try it") }
            Spacer(Modifier.width(8.dp))
            TextButton(onClick = {
                val ttsSettings = Intent("com.android.settings.TTS_SETTINGS").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                try {
                    context.startActivity(ttsSettings)
                } catch (_: ActivityNotFoundException) {
                    try {
                        context.startActivity(Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    } catch (_: ActivityNotFoundException) {
                        Toast.makeText(context, "Couldn't open the phone's settings.", Toast.LENGTH_SHORT).show()
                    }
                }
            }) { Text("Phone's voice settings") }
        }
    }
}
