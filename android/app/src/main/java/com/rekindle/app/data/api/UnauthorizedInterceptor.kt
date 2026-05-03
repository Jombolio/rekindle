package com.rekindle.app.data.api

import com.rekindle.app.core.prefs.PrefsStore
import kotlinx.coroutines.runBlocking
import okhttp3.Interceptor
import okhttp3.Response
import javax.inject.Inject

class UnauthorizedInterceptor @Inject constructor(
    private val prefs: PrefsStore,
) : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        val response = chain.proceed(request)
        // Only clear the token when we actually sent one and the server rejected it.
        // A 401 on the login endpoint (no Authorization header) is expected behaviour.
        if (response.code == 401 && request.header("Authorization") != null) {
            runBlocking { prefs.clearActiveSourceToken() }
        }
        return response
    }
}
