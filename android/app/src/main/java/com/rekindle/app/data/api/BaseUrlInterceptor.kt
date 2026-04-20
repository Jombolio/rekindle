package com.rekindle.app.data.api

import com.rekindle.app.core.prefs.PrefsStore
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.Interceptor
import okhttp3.Response
import javax.inject.Inject

/**
 * Rewrites the host/port of every request to the user-configured server URL.
 * This lets Retrofit be initialised with a placeholder base URL while the
 * actual server is set at runtime (or changed after login).
 */
class BaseUrlInterceptor @Inject constructor(
    private val prefs: PrefsStore,
) : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val serverUrl = runBlocking { prefs.serverUrl.first() }
            .trimEnd('/').ifBlank { return chain.proceed(chain.request()) }

        val base = serverUrl.toHttpUrl()
        val original = chain.request()
        val newUrl = original.url.newBuilder()
            .scheme(base.scheme)
            .host(base.host)
            .port(base.port)
            .build()

        return chain.proceed(original.newBuilder().url(newUrl).build())
    }
}
