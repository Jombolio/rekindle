package com.rekindle.app.data.api

/**
 * Request tag carried by login/setup calls. It pins the request to the URL the
 * user typed (instead of the active source's URL) and tells [AuthInterceptor]
 * not to attach the active source's bearer token — without it, adding a second
 * server would send the new server's credentials to the currently active one.
 */
data class AuthRoute(val baseUrl: String)
