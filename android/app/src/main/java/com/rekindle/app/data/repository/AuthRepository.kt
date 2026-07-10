package com.rekindle.app.data.repository

import com.rekindle.app.core.prefs.PrefsStore
import com.rekindle.app.data.api.AuthRoute
import com.rekindle.app.data.api.RekindleApi
import com.rekindle.app.data.model.LoginRequest
import com.rekindle.app.data.model.SetupRequest
import com.rekindle.app.domain.model.ServerSource
import kotlinx.coroutines.flow.first
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class AuthRepository @Inject constructor(
    private val api: RekindleApi,
    private val prefs: PrefsStore,
) {
    suspend fun login(baseUrl: String, username: String, password: String): Result<Unit> = runCatching {
        val url = baseUrl.trimEnd('/')
        val response = api.login(LoginRequest(username, password), AuthRoute(url))
        commitSource(url, response.token, response.permissionLevel)
    }

    suspend fun setup(baseUrl: String, username: String, password: String, setupToken: String): Result<Unit> = runCatching {
        val url = baseUrl.trimEnd('/')
        val response = api.setup(SetupRequest(username, password, setupToken), AuthRoute(url))
        commitSource(url, response.token, response.permissionLevel)
    }

    val permissionLevel = prefs.permissionLevel

    suspend fun needsSetup(baseUrl: String): Boolean = runCatching {
        api.setupStatus(AuthRoute(baseUrl.trimEnd('/')))["needsSetup"] == true
    }.getOrDefault(false)

    suspend fun logout() {
        val activeId = prefs.activeSourceId.first()
        if (activeId.isNotEmpty()) {
            val sources = prefs.sources.first()
            val source = sources.find { it.id == activeId }
            if (source != null) {
                prefs.addOrUpdateSource(source.copy(token = null))
            }
        }
        prefs.clearToken()
    }

    // ── Private ───────────────────────────────────────────────────────────────

    private suspend fun commitSource(baseUrl: String, token: String, permissionLevel: Int) {
        // Find an existing source with this URL or create a new one.
        val existing = prefs.sources.first().find {
            it.baseUrl.trimEnd('/') == baseUrl.trimEnd('/')
        }
        val source = ServerSource(
            id = existing?.id ?: prefs.newSourceId(),
            name = existing?.name ?: baseUrl.removePrefix("https://").removePrefix("http://"),
            baseUrl = baseUrl.trimEnd('/'),
            token = token,
            permissionLevel = permissionLevel,
        )
        prefs.addOrUpdateSource(source)
        prefs.setActiveSourceId(source.id)
        // A source now exists, so the legacy single-server keys are never read
        // again — clear them so a stale JWT can't linger on disk.
        prefs.clearToken()
    }
}
