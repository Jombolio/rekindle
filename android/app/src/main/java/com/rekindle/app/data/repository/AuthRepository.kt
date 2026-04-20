package com.rekindle.app.data.repository

import com.rekindle.app.core.prefs.PrefsStore
import com.rekindle.app.data.api.RekindleApi
import com.rekindle.app.data.model.LoginRequest
import com.rekindle.app.data.model.SetupRequest
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class AuthRepository @Inject constructor(
    private val api: RekindleApi,
    private val prefs: PrefsStore,
) {
    suspend fun login(username: String, password: String): Result<Unit> = runCatching {
        val response = api.login(LoginRequest(username, password))
        prefs.setToken(response.token)
        prefs.setPermissionLevel(response.permissionLevel)
    }

    suspend fun setup(username: String, password: String, setupToken: String): Result<Unit> = runCatching {
        val response = api.setup(SetupRequest(username, password, setupToken))
        prefs.setToken(response.token)
        prefs.setPermissionLevel(response.permissionLevel)
    }

    val permissionLevel = prefs.permissionLevel

    suspend fun needsSetup(): Boolean = runCatching {
        api.setupStatus()["needsSetup"] == true
    }.getOrDefault(false)

    suspend fun logout() = prefs.clearToken()
}
