package com.rekindle.app.ui.viewmodel

import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.rekindle.app.core.prefs.PrefsStore
import com.rekindle.app.domain.model.ServerSource
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.io.File
import javax.inject.Inject

data class SettingsState(
    val themeMode: String = "system",
    /** Content URI string for the SAF-picked folder, or empty for app-private storage. */
    val downloadSafUri: String = "",
    /** Human-readable label derived from the SAF URI, e.g. "Downloads/Rekindle". */
    val downloadLocationLabel: String = "",
)

@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val prefs: PrefsStore,
    @ApplicationContext private val context: Context,
) : ViewModel() {

    private val _state = MutableStateFlow(SettingsState())
    val state = _state.asStateFlow()

    val sources = prefs.sources.stateIn(viewModelScope, SharingStarted.Eagerly, emptyList())
    val activeSourceId = prefs.activeSourceId.stateIn(viewModelScope, SharingStarted.Eagerly, "")

    /** Absolute path of the app-private downloads directory (always available, no permission). */
    val appPrivatePath: String = File(
        context.getExternalFilesDir(null), "Rekindle Downloads"
    ).absolutePath

    init {
        viewModelScope.launch {
            combine(prefs.themeMode, prefs.downloadSafUri) { theme, safUri ->
                SettingsState(
                    themeMode = theme,
                    downloadSafUri = safUri,
                    downloadLocationLabel = if (safUri.isBlank()) "" else safUriLabel(safUri),
                )
            }.collect { _state.value = it }
        }
    }

    fun setThemeMode(mode: String) {
        viewModelScope.launch { prefs.setThemeMode(mode) }
    }

    /** Persist the URI obtained from ACTION_OPEN_DOCUMENT_TREE. */
    fun setDownloadSafUri(uri: String) {
        viewModelScope.launch { prefs.setDownloadSafUri(uri) }
    }

    /** Revert to app-private storage and release the SAF URI. */
    fun clearDownloadSafUri() {
        viewModelScope.launch { prefs.clearDownloadSafUri() }
    }

    fun switchSource(source: ServerSource) {
        viewModelScope.launch {
            prefs.setActiveSourceId(source.id)
            source.token?.let { prefs.setToken(it) }
            prefs.setPermissionLevel(source.permissionLevel)
            prefs.setServerUrl(source.baseUrl)
        }
    }

    fun removeSource(sourceId: String) {
        viewModelScope.launch { prefs.removeSource(sourceId) }
    }

    fun renameSource(sourceId: String, newName: String) {
        viewModelScope.launch {
            val source = sources.value.find { it.id == sourceId } ?: return@launch
            prefs.addOrUpdateSource(source.copy(name = newName))
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    /**
     * Converts a SAF content URI to a readable path like "Downloads/Rekindle".
     * Falls back to the raw URI string if parsing fails.
     */
    private fun safUriLabel(uriString: String): String = try {
        val uri = Uri.parse(uriString)
        val treeDocId = DocumentsContract.getTreeDocumentId(uri)
        // treeDocId is typically "primary:Downloads/Rekindle" — strip the volume prefix.
        val colonIdx = treeDocId.indexOf(':')
        if (colonIdx >= 0) treeDocId.substring(colonIdx + 1) else treeDocId
    } catch (_: Exception) {
        uriString
    }
}
