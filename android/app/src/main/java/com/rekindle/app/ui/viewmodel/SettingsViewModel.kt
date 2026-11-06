package com.rekindle.app.ui.viewmodel

import android.content.Context
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.rekindle.app.core.prefs.BookFont
import com.rekindle.app.core.prefs.BookTheme
import com.rekindle.app.core.prefs.ReadingStyle
import com.rekindle.app.core.prefs.DEFAULT_BOOK_FONT_SIZE
import com.rekindle.app.core.prefs.DEFAULT_CHAPTER_CONFIRM_MS
import com.rekindle.app.BuildConfig
import com.rekindle.app.core.prefs.PrefsStore
import com.rekindle.app.core.update.AppUpdateChecker
import com.rekindle.app.core.update.UpdateCheck
import com.rekindle.app.domain.model.ServerSource
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.io.File
import javax.inject.Inject

data class SettingsState(
    val themeMode: String = "system",
    /** Content URI string for the SAF-picked folder, or empty for app-private storage. */
    val downloadSafUri: String = "",
    /** Human-readable label derived from the SAF URI, e.g. "Downloads/Rekindle". */
    val downloadLocationLabel: String = "",
    /** Require a second input to leave the current chapter. */
    val confirmChapterChange: Boolean = true,
    /** How long an armed chapter-change confirmation stays open, in milliseconds. */
    val chapterConfirmMs: Int = DEFAULT_CHAPTER_CONFIRM_MS,
    /** The font and text size books open with. */
    val bookFont: BookFont = BookFont.ORIGINAL,
    val bookFontSize: Float = DEFAULT_BOOK_FONT_SIZE,
    /** The theme books open in. */
    val bookTheme: BookTheme = BookTheme.MATCH_APP,
    /** Book layout and readability options. */
    val readingStyle: ReadingStyle = ReadingStyle(),
    /** Offer betas and release candidates when checking for updates. */
    val receivePreReleases: Boolean = false,
    val checkingForUpdates: Boolean = false,
    val updateCheck: UpdateCheck? = null,
)

@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val prefs: PrefsStore,
    @ApplicationContext private val context: Context,
    private val updateChecker: AppUpdateChecker,
) : ViewModel() {

    private val _state = MutableStateFlow(SettingsState())
    val state = _state.asStateFlow()

    val sources = prefs.sources.stateIn(viewModelScope, SharingStarted.Eagerly, emptyList())
    val activeSourceId = prefs.activeSourceId.stateIn(viewModelScope, SharingStarted.Eagerly, "")

    /** F-Droid signs its own builds, so a downloaded APK can't update such an install. */
    val installedFromFdroid: Boolean = installerPackage()?.contains("fdroid", ignoreCase = true) == true

    /** Absolute path of the app-private downloads directory (always available, no permission). */
    val appPrivatePath: String = File(
        context.getExternalFilesDir(null), "Rekindle Downloads"
    ).absolutePath

    init {
        viewModelScope.launch {
            combine(
                prefs.themeMode,
                prefs.downloadSafUri,
                prefs.confirmChapterChange,
                prefs.chapterConfirmMs,
            ) { theme, safUri, confirmChapter, confirmMs ->
                { current: SettingsState ->
                    current.copy(
                        themeMode = theme,
                        downloadSafUri = safUri,
                        downloadLocationLabel = if (safUri.isBlank()) "" else safUriLabel(safUri),
                        confirmChapterChange = confirmChapter,
                        chapterConfirmMs = confirmMs,
                    )
                }
            }.collect { change -> _state.update(change) }
        }
        viewModelScope.launch {
            prefs.receivePreReleases.collect { receive ->
                _state.update { it.copy(receivePreReleases = receive) }
            }
        }
        viewModelScope.launch {
            prefs.bookTheme.collect { theme -> _state.update { it.copy(bookTheme = theme) } }
        }
        viewModelScope.launch {
            prefs.readingStyle.collect { style -> _state.update { it.copy(readingStyle = style) } }
        }
        viewModelScope.launch {
            combine(prefs.bookFont, prefs.bookFontSize) { font, size ->
                font to size
            }.collect { (font, size) ->
                _state.update { it.copy(bookFont = font, bookFontSize = size) }
            }
        }
    }

    fun setThemeMode(mode: String) {
        viewModelScope.launch { prefs.setThemeMode(mode) }
    }

    fun setReceivePreReleases(receive: Boolean) {
        // The last answer was for the other channel.
        _state.update { it.copy(updateCheck = null) }
        viewModelScope.launch { prefs.setReceivePreReleases(receive) }
    }

    fun checkForUpdates() {
        if (_state.value.checkingForUpdates) return
        _state.update { it.copy(checkingForUpdates = true, updateCheck = null) }
        val includePreReleases = _state.value.receivePreReleases
        viewModelScope.launch {
            val result = updateChecker.check(BuildConfig.VERSION_NAME, includePreReleases)
            _state.update { it.copy(checkingForUpdates = false, updateCheck = result) }
        }
    }

    fun setBookFont(font: BookFont) {
        viewModelScope.launch { prefs.setBookFont(font) }
    }

    fun setBookTheme(theme: BookTheme) {
        viewModelScope.launch { prefs.setBookTheme(theme) }
    }

    fun setReadingStyle(style: ReadingStyle) {
        viewModelScope.launch { prefs.setReadingStyle(style) }
    }

    fun setBookFontSize(size: Float) {
        viewModelScope.launch { prefs.setBookFontSize(size) }
    }

    fun setConfirmChapterChange(confirm: Boolean) {
        viewModelScope.launch { prefs.setConfirmChapterChange(confirm) }
    }

    fun setChapterConfirmMs(ms: Int) {
        viewModelScope.launch { prefs.setChapterConfirmMs(ms) }
    }

    /** Persist the URI obtained from ACTION_OPEN_DOCUMENT_TREE. */
    fun setDownloadSafUri(uri: String) {
        viewModelScope.launch { prefs.setDownloadSafUri(uri) }
    }

    /** Revert to app-private storage and release the SAF URI. */
    fun clearDownloadSafUri() {
        viewModelScope.launch { prefs.clearDownloadSafUri() }
    }

    fun switchSource(source: ServerSource) {
        viewModelScope.launch {
            // serverUrl/token/permissionLevel all derive from the active source;
            // writing legacy keys here would leak this source's JWT to others.
            prefs.setActiveSourceId(source.id)
        }
    }

    fun removeSource(sourceId: String) {
        viewModelScope.launch { prefs.removeSource(sourceId) }
    }

    fun renameSource(sourceId: String, newName: String) {
        viewModelScope.launch {
            val source = sources.value.find { it.id == sourceId } ?: return@launch
            prefs.addOrUpdateSource(source.copy(name = newName))
        }
    }

    private fun installerPackage(): String? = runCatching {
        val manager = context.packageManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            manager.getInstallSourceInfo(context.packageName).installingPackageName
        } else {
            @Suppress("DEPRECATION")
            manager.getInstallerPackageName(context.packageName)
        }
    }.getOrNull()

    // ── Helpers ───────────────────────────────────────────────────────────────

    /**
     * Converts a SAF content URI to a readable path like "Downloads/Rekindle".
     * Falls back to the raw URI string if parsing fails.
     */
    private fun safUriLabel(uriString: String): String = try {
        val uri = Uri.parse(uriString)
        val treeDocId = DocumentsContract.getTreeDocumentId(uri)
        // treeDocId is typically "primary:Downloads/Rekindle" — strip the volume prefix.
        val colonIdx = treeDocId.indexOf(':')
        if (colonIdx >= 0) treeDocId.substring(colonIdx + 1) else treeDocId
    } catch (_: Exception) {
        uriString
    }
}
