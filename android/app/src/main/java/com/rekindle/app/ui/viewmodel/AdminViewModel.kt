package com.rekindle.app.ui.viewmodel

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.rekindle.app.core.prefs.PrefsStore
import com.rekindle.app.data.api.RekindleApi
import com.rekindle.app.data.model.CreateUserRequest
import com.rekindle.app.data.model.MediaDto
import com.rekindle.app.data.model.UpdatePasswordRequest
import com.rekindle.app.data.model.UpdatePermissionRequest
import com.rekindle.app.data.model.toDomain
import com.rekindle.app.domain.model.AdminStats
import com.rekindle.app.domain.model.AdminUser
import com.rekindle.app.domain.model.Media
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.concurrent.TimeUnit
import javax.inject.Inject

data class AdminScreenState(
    val users: List<AdminUser> = emptyList(),
    val usersLoading: Boolean = false,
    val usersError: String? = null,
    val stats: AdminStats? = null,
    val statsLoading: Boolean = false,
    val statsError: String? = null,
    val clearingCache: Boolean = false,
    val uploadLoading: Boolean = false,
    val uploadError: String? = null,
    val uploadSuccess: String? = null,
    val uploadFolders: List<Media> = emptyList(),
)

@HiltViewModel
class AdminViewModel @Inject constructor(
    private val api: RekindleApi,
    private val prefs: PrefsStore,
    @ApplicationContext private val context: Context,
) : ViewModel() {

    // Separate upload client with generous timeouts — the shared OkHttpClient
    // has 2-minute timeouts suited to normal API calls, but a large archive
    // can take many minutes to upload over a slow connection.
    private val uploadClient = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.MINUTES)
        .readTimeout(5, TimeUnit.MINUTES)
        .build()

    private val _state = MutableStateFlow(AdminScreenState())
    val state = _state.asStateFlow()

    private val _cacheCleared = MutableSharedFlow<Long>(extraBufferCapacity = 1)
    val cacheCleared = _cacheCleared.asSharedFlow()

    val coverBaseUrl = prefs.serverUrl
        .map { it.trimEnd('/') }
        .stateIn(viewModelScope, SharingStarted.Eagerly, "")

    val authHeader = prefs.token
        .map { "Bearer ${it ?: ""}" }
        .stateIn(viewModelScope, SharingStarted.Eagerly, "Bearer ")

    // ── Users ─────────────────────────────────────────────────────────────────

    fun loadUsers() {
        viewModelScope.launch {
            _state.update { it.copy(usersLoading = true, usersError = null) }
            runCatching { api.getUsers().map { it.toDomain() } }
                .onSuccess { users -> _state.update { it.copy(users = users, usersLoading = false) } }
                .onFailure { e -> _state.update { it.copy(usersLoading = false, usersError = e.message) } }
        }
    }

    fun createUser(username: String, password: String, permissionLevel: Int) {
        viewModelScope.launch {
            runCatching { api.createUser(CreateUserRequest(username, password, permissionLevel)) }
                .onSuccess { loadUsers() }
                .onFailure { e -> _state.update { it.copy(usersError = e.message) } }
        }
    }

    fun updatePermission(userId: String, level: Int) {
        viewModelScope.launch {
            runCatching { api.updateUserPermission(userId, UpdatePermissionRequest(level)) }
                .onSuccess { loadUsers() }
                .onFailure { e -> _state.update { it.copy(usersError = e.message) } }
        }
    }

    fun updatePassword(userId: String, password: String) {
        viewModelScope.launch {
            runCatching { api.updateUserPassword(userId, UpdatePasswordRequest(password)) }
                .onFailure { e -> _state.update { it.copy(usersError = e.message) } }
        }
    }

    fun deleteUser(userId: String) {
        viewModelScope.launch {
            runCatching { api.deleteUser(userId) }
                .onSuccess { loadUsers() }
                .onFailure { e -> _state.update { it.copy(usersError = e.message) } }
        }
    }

    // ── Stats & Cache ─────────────────────────────────────────────────────────

    fun loadStats() {
        viewModelScope.launch {
            _state.update { it.copy(statsLoading = true, statsError = null) }
            runCatching { api.getAdminStats().toDomain() }
                .onSuccess { stats -> _state.update { it.copy(stats = stats, statsLoading = false) } }
                .onFailure { e -> _state.update { it.copy(statsLoading = false, statsError = e.message) } }
        }
    }

    fun clearCache() {
        viewModelScope.launch {
            _state.update { it.copy(clearingCache = true) }
            runCatching { api.clearCache() }
                .onSuccess { resp ->
                    _cacheCleared.tryEmit(resp.freedBytes)
                    loadStats()
                }
            _state.update { it.copy(clearingCache = false) }
        }
    }

    // ── Upload folder autocomplete ────────────────────────────────────────────

    private var _foldersForLibraryId = ""

    fun loadFoldersForLibrary(libraryId: String) {
        if (_foldersForLibraryId == libraryId) return
        _foldersForLibraryId = libraryId
        viewModelScope.launch {
            runCatching { api.getMedia(libraryId, 1, 200) }
                .onSuccess { page ->
                    _state.update {
                        it.copy(uploadFolders = page.items
                            .filter { m -> m.mediaType == "folder" }
                            .map(MediaDto::toDomain))
                    }
                }
        }
    }

    fun clearUploadStatus() {
        _state.update { it.copy(uploadError = null, uploadSuccess = null) }
    }

    // ── Upload ────────────────────────────────────────────────────────────────

    fun uploadFile(fileUri: Uri, libraryId: String, relativePath: String?) {
        viewModelScope.launch {
            _state.update { it.copy(uploadLoading = true, uploadError = null, uploadSuccess = null) }
            runCatching {
                val baseUrl = prefs.serverUrl.first().trimEnd('/')
                val token = prefs.token.first() ?: ""
                val fileName = resolveFileName(fileUri)
                val bytes = context.contentResolver.openInputStream(fileUri)?.use { it.readBytes() }
                    ?: error("Cannot read selected file")

                val filePart = MultipartBody.Part.createFormData(
                    "file", fileName,
                    bytes.toRequestBody("application/octet-stream".toMediaType()),
                )
                val bodyBuilder = MultipartBody.Builder()
                    .setType(MultipartBody.FORM)
                    .addFormDataPart("libraryId", libraryId)
                    .addPart(filePart)
                if (!relativePath.isNullOrBlank()) {
                    bodyBuilder.addFormDataPart("relativePath", relativePath)
                }

                val request = Request.Builder()
                    .url("$baseUrl/api/admin/upload")
                    .header("Authorization", "Bearer $token")
                    .post(bodyBuilder.build())
                    .build()

                val response = uploadClient.newCall(request).execute()
                if (!response.isSuccessful) {
                    val body = response.body?.string() ?: ""
                    val msg = runCatching { JSONObject(body).optString("error") }.getOrNull()
                    error(msg?.ifBlank { null } ?: "HTTP ${response.code}")
                }
                val body = response.body?.string() ?: ""
                JSONObject(body).optString("message", "Upload complete.")
            }
                .onSuccess { msg -> _state.update { it.copy(uploadLoading = false, uploadSuccess = msg) } }
                .onFailure { e -> _state.update { it.copy(uploadLoading = false, uploadError = e.message) } }
        }
    }

    private fun resolveFileName(uri: Uri): String =
        context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            cursor.moveToFirst()
            if (idx >= 0) cursor.getString(idx) else null
        } ?: uri.lastPathSegment ?: "upload"
}
