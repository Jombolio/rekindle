package com.rekindle.app.core.prefs

/**
 * The theme books open in. [MATCH_APP] follows the app: light or dark. The
 * reader's palette button changes the theme only for that visit.
 */
enum class BookTheme(val label: String) {
    MATCH_APP("Match app"),
    LIGHT("Light"),
    DARK("Dark"),
    SEPIA("Sepia"),
    CONTRAST_DARK("High contrast dark"),
    CONTRAST_LIGHT("High contrast light");

    companion object {
        /** Prefs store the name, so an unknown value from another version is harmless. */
        fun parse(name: String?): BookTheme = entries.firstOrNull { it.name == name } ?: MATCH_APP
    }
}
