package com.rekindle.app.core.update

import com.google.gson.JsonElement
import com.google.gson.JsonParser
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.IOException
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton

/** "1.5.0-beta.2"-style version. Pre-releases sort before their release. */
data class SemVersion(
    val major: Int,
    val minor: Int,
    val patch: Int,
    val preRelease: String? = null,
) : Comparable<SemVersion> {

    override fun compareTo(other: SemVersion): Int {
        compareValuesBy(this, other, { it.major }, { it.minor }, { it.patch }).let { if (it != 0) return it }
        val a = preRelease
        val b = other.preRelease
        return when {
            a == null && b == null -> 0
            a == null -> 1
            b == null -> -1
            else -> comparePreRelease(a, b)
        }
    }

    private fun comparePreRelease(a: String, b: String): Int {
        val left = a.split('.')
        val right = b.split('.')
        for (i in 0 until minOf(left.size, right.size)) {
            val l = left[i]
            val r = right[i]
            val ln = l.toIntOrNull()
            val rn = r.toIntOrNull()
            val order = when {
                ln != null && rn != null -> ln.compareTo(rn)
                ln != null -> -1
                rn != null -> 1
                else -> l.compareTo(r)
            }
            if (order != 0) return order
        }
        return left.size.compareTo(right.size)
    }

    override fun toString() = "$major.$minor.$patch" + (preRelease?.let { "-$it" } ?: "")

    companion object {
        private val PATTERN = Regex("""^v?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+.*)?$""")

        fun parse(text: String): SemVersion? {
            val m = PATTERN.matchEntire(text.trim()) ?: return null
            val (major, minor, patch, pre) = m.destructured
            return SemVersion(
                major.toIntOrNull() ?: return null,
                minor.toIntOrNull() ?: return null,
                patch.toIntOrNull() ?: return null,
                pre.ifEmpty { null },
            )
        }
    }
}

/** A published release. [downloadUrl] is the APK, or the release page if it has none. */
data class AppRelease(val version: SemVersion, val downloadUrl: String)

sealed interface UpdateCheck {
    data object UpToDate : UpdateCheck
    data class Available(val release: AppRelease) : UpdateCheck
    data object Failed : UpdateCheck
}

private data class ListedRelease(
    val version: SemVersion,
    val isPreRelease: Boolean,
    val isDraft: Boolean,
    val downloadUrl: String,
)

/** Reads a Gitea or GitHub release list, which name these fields the same way. */
internal fun newestRelease(json: String, includePreReleases: Boolean): AppRelease? =
    JsonParser.parseString(json).asJsonArray
        .mapNotNull { parseRelease(it) }
        .filter { !it.isDraft }
        // A plain version can still be marked pre-release on the host, and the reverse.
        .filter { includePreReleases || (!it.isPreRelease && it.version.preRelease == null) }
        .maxByOrNull { it.version }
        ?.let { AppRelease(it.version, it.downloadUrl) }

private fun parseRelease(element: JsonElement): ListedRelease? {
    val release = element.takeIf { it.isJsonObject }?.asJsonObject ?: return null
    fun string(name: String) = release.get(name)?.takeIf { it.isJsonPrimitive }?.asString
    fun flag(name: String) = release.get(name)?.takeIf { it.isJsonPrimitive }?.asBoolean ?: false

    val version = string("tag_name")?.let(SemVersion::parse) ?: return null
    val apk = release.get("assets")?.takeIf { it.isJsonArray }?.asJsonArray
        ?.mapNotNull { it.takeIf { a -> a.isJsonObject }?.asJsonObject }
        ?.firstOrNull { it.get("name")?.asString?.endsWith(".apk", ignoreCase = true) == true }
        ?.get("browser_download_url")?.asString
    // Only ever handed to the system to open, so nothing but https gets through.
    val url = (apk ?: string("html_url"))?.takeIf { it.startsWith("https://") } ?: return null
    return ListedRelease(version, flag("prerelease"), flag("draft"), url)
}

/**
 * Asks the project's public release lists whether a newer app exists. Runs only when
 * the user asks, and never installs anything: the APK goes to the system, which
 * checks its signature against the installed app.
 *
 * Gitea first and GitHub only if Gitea can't be reached, the same order as the
 * desktop client and server. Has its own HTTP client: the app's shared one attaches
 * the user's server token and rewrites URLs to their server.
 */
@Singleton
class AppUpdateChecker internal constructor(private val sources: List<String>) {

    @Inject
    constructor() : this(SOURCES)

    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    suspend fun check(current: String, includePreReleases: Boolean): UpdateCheck = withContext(Dispatchers.IO) {
        val installed = SemVersion.parse(current)
        for (source in sources) {
            val body = fetch(source) ?: continue
            val parsed = runCatching { newestRelease(body, includePreReleases) }
            if (parsed.isFailure) continue // An unreadable answer, such as a maintenance page.
            val newest = parsed.getOrNull()
            // A source with nothing newer is an answer, not a reason to ask the next.
            return@withContext if (newest != null && (installed == null || newest.version > installed)) {
                UpdateCheck.Available(newest)
            } else {
                UpdateCheck.UpToDate
            }
        }
        UpdateCheck.Failed
    }

    private fun fetch(url: String): String? = try {
        val request = Request.Builder().url(url).header("Accept", "application/json").build()
        client.newCall(request).execute().use { response ->
            if (response.isSuccessful) response.body?.string() else null
        }
    } catch (_: IOException) {
        null
    }

    private companion object {
        val SOURCES = listOf(
            "https://git.jombo.uk/api/v1/repos/Jombo/rekindle/releases?limit=50",
            "https://api.github.com/repos/Jombolio/rekindle/releases?per_page=50",
        )
    }
}
