package com.rekindle.app.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.rekindle.app.core.prefs.PrefsStore
import com.rekindle.app.data.api.RekindleApi
import com.rekindle.app.data.model.CreateLibraryRequest
import com.rekindle.app.data.model.UpdateLibraryRequest
import com.rekindle.app.data.model.toDomain
import com.rekindle.app.data.repository.AuthRepository
import com.rekindle.app.domain.model.Library
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class LibraryState(
    val libraries: List<Library> = emptyList(),
    val loading: Boolean = true,
    val scanning: String? = null,
    val error: String? = null,
)

@HiltViewModel
class LibraryViewModel @Inject constructor(
    private val api: RekindleApi,
    private val authRepo: AuthRepository,
    private val prefs: PrefsStore,
) : ViewModel() {

    private val _state = MutableStateFlow(LibraryState())
    val state = _state.asStateFlow()

    val isAdmin = prefs.permissionLevel.map { it >= 4 }.stateIn(
        viewModelScope,
        SharingStarted.Eagerly,
        false,
    )

    init { load() }

    fun load() {
        viewModelScope.launch {
            _state.update { it.copy(loading = true, error = null) }
            runCatching { api.getLibraries().map { it.toDomain() } }
                .onSuccess { libs -> _state.update { it.copy(libraries = libs, loading = false) } }
                .onFailure { e -> _state.update { it.copy(loading = false, error = e.message) } }
        }
    }

    fun create(name: String, rootPath: String, type: String) {
        viewModelScope.launch {
            runCatching { api.createLibrary(CreateLibraryRequest(name, rootPath, type)) }
                .onSuccess { load() }
                .onFailure { e -> _state.update { it.copy(error = e.message) } }
        }
    }

    fun update(id: String, name: String, rootPath: String, type: String) {
        viewModelScope.launch {
            runCatching { api.updateLibrary(id, UpdateLibraryRequest(name, rootPath, type)) }
                .onSuccess { load() }
                .onFailure { e -> _state.update { it.copy(error = e.message) } }
        }
    }

    fun scan(libraryId: String) {
        viewModelScope.launch {
            _state.update { it.copy(scanning = libraryId) }
            runCatching { api.scanLibrary(libraryId) }
            _state.update { it.copy(scanning = null) }
            load()
        }
    }

    fun delete(libraryId: String) {
        viewModelScope.launch {
            runCatching { api.deleteLibrary(libraryId) }
                .onSuccess { load() }
                .onFailure { e -> _state.update { it.copy(error = e.message) } }
        }
    }

    fun logout() { viewModelScope.launch { authRepo.logout() } }
}
