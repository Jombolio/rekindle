package com.rekindle.app.core.update

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AppUpdatesTest {

    private fun release(
        tag: String,
        pre: Boolean = false,
        draft: Boolean = false,
        apk: String? = "https://host/$tag/RekindleAndroid.apk",
    ): String {
        val assets = if (apk == null) "" else """{"name":"RekindleAndroid.apk","browser_download_url":"$apk"}"""
        return """{"tag_name":"$tag","prerelease":$pre,"draft":$draft,"html_url":"https://host/$tag","assets":[$assets]}"""
    }

    private fun feed(vararg releases: String) = releases.joinToString(",", "[", "]")

    @Test
    fun `parses versions with and without a v, pre-release or build`() {
        assertEquals(SemVersion(1, 5, 0), SemVersion.parse("v1.5.0"))
        assertEquals(SemVersion(1, 5, 0, "beta.2"), SemVersion.parse("1.5.0-beta.2"))
        assertEquals(SemVersion(1, 5, 0), SemVersion.parse("1.5.0+abc"))
        assertNull(SemVersion.parse("latest"))
    }

    @Test
    fun `pre-releases sort before their release, numerically`() {
        fun v(s: String) = SemVersion.parse(s)!!
        assertTrue(v("1.5.0-beta.2") < v("1.5.0"))
        assertTrue(v("1.5.0-beta.2") < v("1.5.0-beta.10"))
        assertTrue(v("1.5.0-alpha") < v("1.5.0-beta"))
        assertTrue(v("1.5.0") < v("1.5.1-beta.1"))
    }

    @Test
    fun `stable channel ignores pre-releases, however they are marked`() {
        val json = feed(
            release("v1.6.0-beta.1", pre = true),
            release("v1.7.0", pre = true),
            release("v1.6.0-rc.1"),
            release("v1.5.0"),
        )
        assertEquals(SemVersion(1, 5, 0), newestRelease(json, includePreReleases = false)?.version)
    }

    @Test
    fun `pre-release channel picks the highest of everything`() {
        val json = feed(release("v1.5.0"), release("v1.6.0-beta.1", pre = true), release("v1.6.0-beta.10", pre = true))
        assertEquals(SemVersion(1, 6, 0, "beta.10"), newestRelease(json, includePreReleases = true)?.version)
    }

    @Test
    fun `drafts and unparsable tags are ignored`() {
        val json = feed(release("v9.0.0", draft = true), release("nightly"), release("v1.0.0"))
        assertEquals(SemVersion(1, 0, 0), newestRelease(json, includePreReleases = true)?.version)
    }

    @Test
    fun `links to the APK, or the release page when there isn't one`() {
        assertEquals(
            "https://host/v1.0.0/RekindleAndroid.apk",
            newestRelease(feed(release("v1.0.0")), false)?.downloadUrl,
        )
        assertEquals("https://host/v1.0.0", newestRelease(feed(release("v1.0.0", apk = null)), false)?.downloadUrl)
    }

    @Test
    fun `refuses to link anywhere but https`() {
        val json = """[{"tag_name":"v1.0.0","html_url":"javascript:alert(1)","assets":[{"name":"a.apk","browser_download_url":"http://host/a.apk"}]}]"""
        assertNull(newestRelease(json, false))
    }

    @Test
    fun `nothing suitable is no release`() {
        assertNull(newestRelease("[]", true))
    }
}
