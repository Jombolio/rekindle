package com.rekindle.app.core.prefs

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

private val Context.dataStore: DataStore<Preferences> by preferencesDataStore("rekindle_prefs")

@Singleton
class PrefsStore @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    private val store = context.dataStore

    val serverUrl: Flow<String> = store.data.map { it[Keys.SERVER_URL] ?: "" }
    val token: Flow<String?> = store.data.map { it[Keys.TOKEN] }
    val permissionLevel: Flow<Int> = store.data.map { it[Keys.PERMISSION_LEVEL] ?: 2 }
    val themeMode: Flow<String> = store.data.map { it[Keys.THEME_MODE] ?: "system" }
    val downloadDirectory: Flow<String> = store.data.map { it[Keys.DOWNLOAD_DIR] ?: "" }

    fun isRtl(mediaId: String): Flow<Boolean> =
        store.data.map { it[booleanPreferencesKey("rtl_$mediaId")] ?: false }

    fun isDoublePage(mediaId: String): Flow<Boolean> =
        store.data.map { it[booleanPreferencesKey("double_page_$mediaId")] ?: false }

    suspend fun setServerUrl(url: String) =
        store.edit { it[Keys.SERVER_URL] = url }

    suspend fun setToken(token: String) =
        store.edit { it[Keys.TOKEN] = token }

    suspend fun clearToken() =
        store.edit {
            it.remove(Keys.TOKEN)
            it.remove(Keys.PERMISSION_LEVEL)
        }

    suspend fun setPermissionLevel(level: Int) =
        store.edit { it[Keys.PERMISSION_LEVEL] = level }

    suspend fun setThemeMode(mode: String) =
        store.edit { it[Keys.THEME_MODE] = mode }

    suspend fun setDownloadDirectory(path: String) =
        store.edit { it[Keys.DOWNLOAD_DIR] = path }

    suspend fun setRtl(mediaId: String, rtl: Boolean) =
        store.edit { it[booleanPreferencesKey("rtl_$mediaId")] = rtl }

    suspend fun setDoublePage(mediaId: String, doublePage: Boolean) =
        store.edit { it[booleanPreferencesKey("double_page_$mediaId")] = doublePage }

    private object Keys {
        val SERVER_URL = stringPreferencesKey("server_url")
        val TOKEN = stringPreferencesKey("jwt_token")
        val PERMISSION_LEVEL = intPreferencesKey("permission_level")
        val THEME_MODE = stringPreferencesKey("theme_mode")
        val DOWNLOAD_DIR = stringPreferencesKey("download_directory")
    }
}
