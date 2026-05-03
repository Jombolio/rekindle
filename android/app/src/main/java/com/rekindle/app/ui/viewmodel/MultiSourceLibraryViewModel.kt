package com.rekindle.app.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.rekindle.app.core.prefs.PrefsStore
import com.rekindle.app.data.model.ScanProgressDto
import com.rekindle.app.domain.model.Library
import com.rekindle.app.domain.model.ServerSource
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit
import javax.inject.Inject

data class SourceLibraryState(
    val source: ServerSource,
    val libraries: List<Library> = emptyList(),
    val loading: Boolean = true,
    val error: String? = null,
    val scanning: String? = null,
    val scanProgress: ScanProgressDto? = null,
)

@HiltViewModel
class MultiSourceLibraryViewModel @Inject constructor(
    private val prefs: PrefsStore,
) : ViewModel() {

    private val http = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .build()

    private val _states = MutableStateFlow<List<SourceLibraryState>>(emptyList())
    val states = _states.asStateFlow()

    init {
        viewModelScope.launch {
            prefs.sources.collect { sources ->
                val current = _states.value.associateBy { it.source.id }
                _states.value = sources.map { source ->
                    current[source.id]?.copy(source = source) ?: SourceLibraryState(source)
                }
                sources.forEach { source ->
                    val existing = current[source.id]
                    // Fetch when the source is new, OR when the token has changed
                    // (covers re-authentication after sign-out/sign-in).
                    if (existing == null || existing.source.token != source.token) {
                        fetchLibraries(source)
                    }
                }
            }
        }
    }

    fun refresh(sourceId: String) {
        val source = stateFor(sourceId)?.source ?: return
        fetchLibraries(source)
    }

    // ── Library CRUD ──────────────────────────────────────────────────────────

    fun createLibrary(sourceId: String, name: String, rootPath: String, type: String) {
        val source = stateFor(sourceId)?.source ?: return
        viewModelScope.launch {
            runCatching {
                apiCall(source, "POST", "api/libraries", JSONObject().apply {
                    put("name", name); put("rootPath", rootPath); put("type", type)
                }.toString())
            }.onSuccess { fetchLibraries(source) }
              .onFailure { e -> updateState(sourceId) { it.copy(error = e.describe()) } }
        }
    }

    fun updateLibrary(sourceId: String, libraryId: String, name: String, rootPath: String, type: String) {
        val source = stateFor(sourceId)?.source ?: return
        viewModelScope.launch {
            runCatching {
                apiCall(source, "PUT", "api/libraries/$libraryId", JSONObject().apply {
                    put("name", name); put("rootPath", rootPath); put("type", type)
                }.toString())
            }.onSuccess { fetchLibraries(source) }
              .onFailure { e -> updateState(sourceId) { it.copy(error = e.describe()) } }
        }
    }

    fun deleteLibrary(sourceId: String, libraryId: String) {
        val source = stateFor(sourceId)?.source ?: return
        viewModelScope.launch {
            runCatching { apiCall(source, "DELETE", "api/libraries/$libraryId") }
                .onSuccess { fetchLibraries(source) }
                .onFailure { e -> updateState(sourceId) { it.copy(error = e.describe()) } }
        }
    }

    // ── Scan ──────────────────────────────────────────────────────────────────

    fun scan(sourceId: String, libraryId: String) {
        val source = stateFor(sourceId)?.source ?: return
        viewModelScope.launch {
            updateState(sourceId) { it.copy(scanning = libraryId, scanProgress = null) }
            runCatching { apiCall(source, "POST", "api/libraries/$libraryId/scan") }
            val deadline = System.currentTimeMillis() + 5 * 60_000L
            while (System.currentTimeMillis() < deadline) {
                delay(1_000)
                val progress = runCatching {
                    withContext(Dispatchers.IO) {
                        val resp = http.newCall(
                            Request.Builder()
                                .url("${source.baseUrl.trimEnd('/')}/api/libraries/$libraryId/scan/progress")
                                .header("Authorization", "Bearer ${source.token ?: ""}")
                                .build()
                        ).execute()
                        if (resp.isSuccessful) parseScanProgress(resp.body?.string() ?: "{}") else null
                    }
                }.getOrNull()
                updateState(sourceId) { it.copy(scanProgress = progress) }
                if (progress?.phase == "complete") break
            }
            updateState(sourceId) { it.copy(scanning = null, scanProgress = null) }
            fetchLibraries(source)
        }
    }

    // ── Source management ─────────────────────────────────────────────────────

    /** Sets this source as active so the singleton Retrofit client points at it. */
    fun setActiveSource(sourceId: String) {
        viewModelScope.launch { prefs.setActiveSourceId(sourceId) }
    }

    fun renameSource(sourceId: String, newName: String) {
        viewModelScope.launch {
            val source = stateFor(sourceId)?.source ?: return@launch
            prefs.addOrUpdateSource(source.copy(name = newName.ifBlank { source.baseUrl }))
        }
    }

    fun signOut(sourceId: String) {
        viewModelScope.launch {
            val source = stateFor(sourceId)?.source ?: return@launch
            prefs.addOrUpdateSource(source.copy(token = null, permissionLevel = 0))
        }
    }

    fun removeSource(sourceId: String) {
        viewModelScope.launch { prefs.removeSource(sourceId) }
    }

    // ── Internals ─────────────────────────────────────────────────────────────

    private fun fetchLibraries(source: ServerSource) {
        viewModelScope.launch {
            val token = source.token ?: run {
                updateState(source.id) { it.copy(loading = false, libraries = emptyList(), error = null) }
                return@launch
            }
            updateState(source.id) { it.copy(loading = true, error = null) }
            runCatching {
                withContext(Dispatchers.IO) {
                    val resp = http.newCall(
                        Request.Builder()
                            .url("${source.baseUrl.trimEnd('/')}/api/libraries")
                            .header("Authorization", "Bearer $token")
                            .build()
                    ).execute()
                    if (!resp.isSuccessful) error("HTTP ${resp.code}")
                    parseLibraries(resp.body?.string() ?: "[]")
                }
            }
                .onSuccess { libs -> updateState(source.id) { it.copy(libraries = libs, loading = false) } }
                .onFailure { e -> updateState(source.id) { it.copy(loading = false, error = e.describe()) } }
        }
    }

    private suspend fun apiCall(
        source: ServerSource,
        method: String,
        path: String,
        jsonBody: String? = null,
    ) = withContext(Dispatchers.IO) {
        val body = jsonBody?.toRequestBody("application/json".toMediaType())
        val req = Request.Builder()
            .url("${source.baseUrl.trimEnd('/')}/$path")
            .header("Authorization", "Bearer ${source.token ?: ""}")
            .method(method, body ?: if (method == "GET" || method == "DELETE") null
                    else "".toRequestBody())
            .build()
        val resp = http.newCall(req).execute()
        if (!resp.isSuccessful) error("HTTP ${resp.code}")
    }

    private fun stateFor(sourceId: String): SourceLibraryState? =
        _states.value.find { it.source.id == sourceId }

    private fun updateState(id: String, t: (SourceLibraryState) -> SourceLibraryState) {
        _states.update { list -> list.map { if (it.source.id == id) t(it) else it } }
    }

    private fun parseLibraries(json: String): List<Library> {
        val arr = JSONArray(json)
        return buildList {
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                add(Library(
                    id = o.getString("id"),
                    name = o.getString("name"),
                    path = o.optString("rootPath", ""),
                    type = o.optString("type", "comic"),
                ))
            }
        }
    }

    private fun parseScanProgress(json: String): ScanProgressDto {
        val o = JSONObject(json)
        return ScanProgressDto(
            phase           = o.optString("phase", ""),
            filesProcessed  = o.optInt("filesProcessed", 0),
            filesTotal      = o.optInt("filesTotal", 0),
            added           = o.optInt("added", 0),
            removed         = o.optInt("removed", 0),
            coversQueued    = o.optInt("coversQueued", 0),
            coversGenerated = o.optInt("coversGenerated", 0),
        )
    }

    // Produce a non-null, human-readable error message from any Throwable.
    private fun Throwable.describe(): String =
        message?.ifBlank { null } ?: "${this::class.simpleName ?: "Error"}"
}
