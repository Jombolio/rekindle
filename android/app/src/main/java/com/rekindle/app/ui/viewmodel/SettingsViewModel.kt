package com.rekindle.app.ui.viewmodel

import android.content.Context
import android.os.Environment
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
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.io.File
import javax.inject.Inject

data class SettingsState(
    val themeMode: String = "system",
    val downloadDirectory: String = "",
    val defaultDownloadDir: String = "",
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

    init {
        val defaultDir = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
            "Rekindle",
        ).absolutePath

        viewModelScope.launch {
            combine(prefs.themeMode, prefs.downloadDirectory) { theme, dir ->
                SettingsState(themeMode = theme, downloadDirectory = dir, defaultDownloadDir = defaultDir)
            }.collect { _state.value = it }
        }
    }

    fun setThemeMode(mode: String) {
        viewModelScope.launch { prefs.setThemeMode(mode) }
    }

    fun setDownloadDirectory(path: String) {
        _state.update { it.copy(downloadDirectory = path) }
        viewModelScope.launch { prefs.setDownloadDirectory(path) }
    }

    fun switchSource(source: ServerSource) {
        viewModelScope.launch {
            prefs.setActiveSourceId(source.id)
            // Keep legacy interceptor keys in sync
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
}
