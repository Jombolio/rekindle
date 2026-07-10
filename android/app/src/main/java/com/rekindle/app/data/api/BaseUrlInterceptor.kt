package com.rekindle.app.data.api

import com.rekindle.app.core.prefs.PrefsStore
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.Interceptor
import okhttp3.Response
import java.io.IOException
import javax.inject.Inject

/**
 * Rewrites the host/port of every request to the user-configured server URL.
 * This lets Retrofit be initialised with a placeholder base URL while the
 * actual server is set at runtime (or changed after login).
 *
 * Login/setup requests carry an [AuthRoute] tag whose URL wins over the
 * active source, so signing in to a new server reaches that server.
 */
class BaseUrlInterceptor @Inject constructor(
    private val prefs: PrefsStore,
) : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val override = chain.request().tag(AuthRoute::class.java)?.baseUrl
        val serverUrl = (override ?: runBlocking { prefs.serverUrl.first() })
            .trimEnd('/').ifBlank { return chain.proceed(chain.request()) }

        // IOException fails just this call; anything else would kill the
        // process on OkHttp's dispatcher thread.
        val base = serverUrl.toHttpUrlOrNull()
            ?: throw IOException("Invalid server URL: $serverUrl")
        val original = chain.request()
        val newUrl = original.url.newBuilder()
            .scheme(base.scheme)
            .host(base.host)
            .port(base.port)
            .build()

        return chain.proceed(original.newBuilder().url(newUrl).build())
    }
}
