package com.rekindle.app.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.rekindle.app.core.prefs.PrefsStore
import com.rekindle.app.data.repository.AuthRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class LoginState(
    val serverUrl: String = "",
    val username: String = "",
    val password: String = "",
    val setupToken: String = "",
    val isSetupMode: Boolean = false,
    val loading: Boolean = false,
    val error: String? = null,
    val loginSuccess: Boolean = false,
)

@HiltViewModel
class LoginViewModel @Inject constructor(
    private val authRepo: AuthRepository,
    private val prefs: PrefsStore,
) : ViewModel() {

    private val _state = MutableStateFlow(LoginState())
    val state = _state.asStateFlow()

    init {
        viewModelScope.launch {
            val savedUrl = prefs.serverUrl.first()
            _state.update { it.copy(serverUrl = savedUrl) }
        }
    }

    fun onServerUrlChange(v: String) = _state.update { it.copy(serverUrl = v, error = null) }
    fun onUsernameChange(v: String) = _state.update { it.copy(username = v, error = null) }
    fun onPasswordChange(v: String) = _state.update { it.copy(password = v, error = null) }
    fun onSetupTokenChange(v: String) = _state.update { it.copy(setupToken = v, error = null) }
    fun toggleSetupMode() = _state.update { it.copy(isSetupMode = !it.isSetupMode, error = null) }

    fun submit() {
        val s = _state.value
        if (s.serverUrl.isBlank() || s.username.isBlank() || s.password.isBlank()) {
            _state.update { it.copy(error = "All fields are required") }
            return
        }
        if (s.isSetupMode && s.setupToken.isBlank()) {
            _state.update { it.copy(error = "Setup token is required — check the server log") }
            return
        }
        viewModelScope.launch {
            _state.update { it.copy(loading = true, error = null) }
            prefs.setServerUrl(s.serverUrl.trimEnd('/'))

            val result = if (s.isSetupMode) {
                authRepo.setup(s.username, s.password, s.setupToken)
            } else {
                authRepo.login(s.username, s.password)
            }

            result
                .onSuccess { _state.update { it.copy(loading = false, loginSuccess = true) } }
                .onFailure { e ->
                    val msg = when {
                        e.message?.contains("401") == true ->
                            if (s.isSetupMode) "Invalid setup token or credentials."
                            else "Invalid username or password."
                        e.message?.contains("409") == true ->
                            "Admin already exists — switch to Sign In."
                        else -> e.message ?: "Unexpected error"
                    }
                    _state.update { it.copy(loading = false, error = msg) }
                }
        }
    }
}
