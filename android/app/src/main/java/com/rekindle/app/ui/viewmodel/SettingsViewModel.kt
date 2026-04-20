package com.rekindle.app.ui.viewmodel

import android.content.Context
import android.os.Environment
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.rekindle.app.core.prefs.PrefsStore
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
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
}
