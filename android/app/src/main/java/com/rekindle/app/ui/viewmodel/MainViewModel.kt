package com.rekindle.app.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.rekindle.app.core.prefs.PrefsStore
import com.rekindle.app.ui.Screen
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class MainViewModel @Inject constructor(
    prefs: PrefsStore,
) : ViewModel() {

    /**
     * Null while DataStore is still being read (usually < 100 ms).
     * Once resolved:
     *   • non-blank token + server URL  → skip login, go straight to Libraries
     *   • anything else                  → show Login
     */
    val startDestination: StateFlow<String?> = combine(
        prefs.token,
        prefs.serverUrl,
    ) { token, serverUrl ->
        if (!token.isNullOrBlank() && serverUrl.isNotBlank()) {
            Screen.Libraries.route
        } else {
            Screen.Login.route
        }
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.Eagerly,
        initialValue = null,
    )

    /**
     * Emits once when the active source's token transitions from non-null to null
     * at runtime (e.g. server restarted and invalidated the JWT). The NavGraph
     * listens to this and pops back to Libraries so the sign-in prompt is shown.
     */
    private val _tokenLost = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
    val tokenLost: SharedFlow<Unit> = _tokenLost.asSharedFlow()

    init {
        viewModelScope.launch {
            var prevToken: String? = "sentinel"
            prefs.activeSource.collect { source ->
                val token = source?.token
                if (prevToken != null && prevToken != "sentinel" && token == null) {
                    _tokenLost.tryEmit(Unit)
                }
                prevToken = token
            }
        }
    }
}
