package com.rekindle.app.data.api

import com.rekindle.app.core.prefs.PrefsStore
import kotlinx.coroutines.runBlocking
import okhttp3.Interceptor
import okhttp3.Response
import javax.inject.Inject

/** Response header carrying a replacement JWT issued by the server. */
const val TOKEN_RENEWAL_HEADER = "X-Rekindle-Token"

/**
 * Persists replacement tokens the server hands back shortly before the current
 * one expires.
 *
 * JWTs have a hard absolute expiry and there is no refresh-token flow, so without
 * this the session dies mid-use once that deadline passes and the only way back
 * in is a manual sign-out and sign-in. The header only appears inside the renewal
 * window and stops as soon as the new token is in use, so this costs one write
 * per renewal rather than one per request.
 *
 * Requests on this client always go to the active source (BaseUrlInterceptor
 * rewrites the host, AuthInterceptor attaches that source's token), so the
 * replacement always belongs to the active source.
 */
class TokenRenewalInterceptor @Inject constructor(
    private val prefs: PrefsStore,
) : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val response = chain.proceed(chain.request())
        response.header(TOKEN_RENEWAL_HEADER)?.let { renewed ->
            runBlocking { prefs.renewActiveSourceToken(renewed) }
        }
        return response
    }
}
