package com.rekindle.app.core.prefs

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.floatPreferencesKey
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import com.rekindle.app.domain.model.ServerSource
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

private val Context.dataStore: DataStore<Preferences> by preferencesDataStore("rekindle_prefs")

@Singleton
class PrefsStore @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    private val store = context.dataStore
    private val gson = Gson()
    private val sourceListType = object : TypeToken<List<ServerSource>>() {}.type

    // ── Multi-source ──────────────────────────────────────────────────────────

    val sources: Flow<List<ServerSource>> = store.data.map { prefs ->
        val json = prefs[Keys.SOURCES_JSON] ?: "[]"
        runCatching<List<ServerSource>> { gson.fromJson(json, sourceListType) }
            .getOrDefault(emptyList())
    }

    val activeSourceId: Flow<String> = store.data.map { it[Keys.ACTIVE_SOURCE_ID] ?: "" }

    val activeSource: Flow<ServerSource?> = combine(sources, activeSourceId) { list, id ->
        list.find { it.id == id } ?: list.firstOrNull()
    }

    suspend fun addOrUpdateSource(source: ServerSource) {
        store.edit { prefs ->
            val current = runCatching<List<ServerSource>> {
                gson.fromJson(prefs[Keys.SOURCES_JSON] ?: "[]", sourceListType)
            }.getOrDefault(emptyList()).toMutableList()
            val idx = current.indexOfFirst { it.id == source.id }
            if (idx >= 0) current[idx] = source else current.add(source)
            prefs[Keys.SOURCES_JSON] = gson.toJson(current)
        }
    }

    suspend fun removeSource(id: String) {
        store.edit { prefs ->
            val current = runCatching<List<ServerSource>> {
                gson.fromJson(prefs[Keys.SOURCES_JSON] ?: "[]", sourceListType)
            }.getOrDefault(emptyList()).filter { it.id != id }
            prefs[Keys.SOURCES_JSON] = gson.toJson(current)
            if (prefs[Keys.ACTIVE_SOURCE_ID] == id) prefs.remove(Keys.ACTIVE_SOURCE_ID)
        }
    }

    suspend fun setActiveSourceId(id: String) =
        store.edit { it[Keys.ACTIVE_SOURCE_ID] = id }

    /** Creates a new source ID for a fresh login. */
    fun newSourceId(): String = UUID.randomUUID().toString()

    // ── Active-source derived values ──────────────────────────────────────────
    // These delegate to the active source, with fallback to legacy single-server
    // prefs so existing installations continue to work without re-login.

    val serverUrl: Flow<String> = combine(activeSource, store.data) { source, prefs ->
        source?.baseUrl ?: prefs[Keys.SERVER_URL] ?: ""
    }

    val token: Flow<String?> = combine(activeSource, store.data) { source, prefs ->
        source?.token ?: prefs[Keys.TOKEN]
    }

    val permissionLevel: Flow<Int> = combine(activeSource, store.data) { source, prefs ->
        source?.permissionLevel ?: prefs[Keys.PERMISSION_LEVEL] ?: 2
    }

    // Legacy setters — still used during login before the source is committed.
    suspend fun setServerUrl(url: String) =
        store.edit { it[Keys.SERVER_URL] = url }

    suspend fun setToken(token: String) =
        store.edit { it[Keys.TOKEN] = token }

    suspend fun setPermissionLevel(level: Int) =
        store.edit { it[Keys.PERMISSION_LEVEL] = level }

    suspend fun clearToken() =
        store.edit {
            it.remove(Keys.TOKEN)
            it.remove(Keys.PERMISSION_LEVEL)
        }

    // ── App settings ──────────────────────────────────────────────────────────

    val themeMode: Flow<String> = store.data.map { it[Keys.THEME_MODE] ?: "system" }
    val downloadDirectory: Flow<String> = store.data.map { it[Keys.DOWNLOAD_DIR] ?: "" }
    val spineGap: Flow<Float> = store.data.map { it[Keys.SPINE_GAP] ?: 0f }

    suspend fun setThemeMode(mode: String) =
        store.edit { it[Keys.THEME_MODE] = mode }

    suspend fun setDownloadDirectory(path: String) =
        store.edit { it[Keys.DOWNLOAD_DIR] = path }

    suspend fun setSpineGap(gap: Float) =
        store.edit { it[Keys.SPINE_GAP] = gap }

    // ── Per-media reader prefs ────────────────────────────────────────────────

    fun isRtl(mediaId: String): Flow<Boolean> =
        store.data.map { it[booleanPreferencesKey("rtl_$mediaId")] ?: false }

    fun isRtlExplicit(mediaId: String): Flow<Boolean?> =
        store.data.map { it[booleanPreferencesKey("rtl_$mediaId")] }

    fun isDoublePage(mediaId: String): Flow<Boolean> =
        store.data.map { it[booleanPreferencesKey("double_page_$mediaId")] ?: false }

    fun isScrollMode(mediaId: String): Flow<Boolean> =
        store.data.map { it[booleanPreferencesKey("scroll_mode_$mediaId")] ?: false }

    suspend fun setRtl(mediaId: String, rtl: Boolean) =
        store.edit { it[booleanPreferencesKey("rtl_$mediaId")] = rtl }

    suspend fun setDoublePage(mediaId: String, doublePage: Boolean) =
        store.edit { it[booleanPreferencesKey("double_page_$mediaId")] = doublePage }

    suspend fun setScrollMode(mediaId: String, scrollMode: Boolean) =
        store.edit { it[booleanPreferencesKey("scroll_mode_$mediaId")] = scrollMode }

    private object Keys {
        val SERVER_URL = stringPreferencesKey("server_url")
        val TOKEN = stringPreferencesKey("jwt_token")
        val PERMISSION_LEVEL = intPreferencesKey("permission_level")
        val THEME_MODE = stringPreferencesKey("theme_mode")
        val DOWNLOAD_DIR = stringPreferencesKey("download_directory")
        val SPINE_GAP = floatPreferencesKey("spine_gap")
        val SOURCES_JSON = stringPreferencesKey("sources_json")
        val ACTIVE_SOURCE_ID = stringPreferencesKey("active_source_id")
    }
}
