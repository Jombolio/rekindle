package com.rekindle.app.ui.screens

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.RestartAlt
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import com.rekindle.app.core.prefs.BookAlign
import com.rekindle.app.core.prefs.BookFont
import com.rekindle.app.core.prefs.BookLayout
import com.rekindle.app.core.prefs.BookTheme
import com.rekindle.app.core.prefs.MAX_BOOK_FONT_SIZE
import com.rekindle.app.core.prefs.MIN_BOOK_FONT_SIZE
import com.rekindle.app.core.prefs.ReadingStyle
import kotlin.math.roundToInt

/**
 * Every reading option for books: layout, font, size, theme, spacing, line width,
 * alignment, bold text, page-turn animation and the reading ruler. Shown in Settings
 * and in the reader's options sheet; changes apply at once.
 */
@Composable
fun ReadingOptions(
    style: ReadingStyle,
    font: BookFont,
    fontSize: Float,
    theme: BookTheme,
    onStyle: (ReadingStyle) -> Unit,
    onFont: (BookFont) -> Unit,
    onFontSize: (Float) -> Unit,
    onTheme: (BookTheme) -> Unit,
    modifier: Modifier = Modifier,
) {
    fun ems(v: Float) = if (v == 0f) "None" else "%.2f em".format(v)

    Column(modifier) {
        Heading("Layout")
        Choices(BookLayout.entries, style.layout, { it.label }) { onStyle(style.copy(layout = it)) }

        Heading("Font")
        Choices(BookFont.entries, font, { it.label }, fontOf = ::previewFamily) { onFont(it) }
        SliderRow(
            label = "Text size",
            value = fontSize,
            range = MIN_BOOK_FONT_SIZE..MAX_BOOK_FONT_SIZE,
            steps = (MAX_BOOK_FONT_SIZE - MIN_BOOK_FONT_SIZE).toInt() - 1,
            display = fontSize.toInt().toString(),
        ) { onFontSize(it.roundToInt().toFloat()) }

        Heading("Theme")
        Choices(BookTheme.entries, theme, { it.label }) { onTheme(it) }

        Heading("Spacing")
        SliderRow("Line spacing", style.lineHeight, ReadingStyle.LINE_HEIGHT, 11, "%.1f×".format(style.lineHeight)) {
            onStyle(style.copy(lineHeight = it))
        }
        SliderRow("Letter spacing", style.letterSpacing, ReadingStyle.LETTER_SPACING, 7, ems(style.letterSpacing)) {
            onStyle(style.copy(letterSpacing = it))
        }
        SliderRow("Word spacing", style.wordSpacing, ReadingStyle.WORD_SPACING, 11, ems(style.wordSpacing)) {
            onStyle(style.copy(wordSpacing = it))
        }
        SliderRow(
            "Paragraph spacing",
            style.paragraphSpacing,
            ReadingStyle.PARAGRAPH_SPACING,
            7,
            if (style.paragraphSpacing == 0f) "Book's own" else "%.2f em".format(style.paragraphSpacing),
        ) { onStyle(style.copy(paragraphSpacing = it)) }

        Heading("Page")
        // An em holds about two characters of running text.
        SliderRow("Line width", style.measure, ReadingStyle.MEASURE, 17, "~${(style.measure * 2).roundToInt()} characters") {
            onStyle(style.copy(measure = it.roundToInt().toFloat()))
        }
        Text("Alignment", style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 8.dp))
        Choices(BookAlign.entries, style.align, { it.label }) { onStyle(style.copy(align = it)) }

        Heading("Accessibility")
        SwitchRow("Bold text", null, style.bold) { onStyle(style.copy(bold = it)) }
        SwitchRow("Page-turn animation", "Off, pages change at once.", style.animations) {
            onStyle(style.copy(animations = it))
        }
        SwitchRow("Reading ruler", "A band to keep your place, with the rest dimmed. Drag its edge to move it.", style.ruler) {
            onStyle(style.copy(ruler = it))
        }
        TextButton(onClick = { onStyle(ReadingStyle(layout = style.layout)) }) {
            Icon(Icons.Default.RestartAlt, null)
            Spacer(Modifier.width(8.dp))
            Text("Reset layout and spacing")
        }
    }
}

/** Each bundled font's name is shown in that font, to choose by eye. */
private fun previewFamily(font: BookFont): FontFamily? = when (font) {
    BookFont.SERIF -> FontFamily.Serif
    BookFont.SANS -> FontFamily.SansSerif
    BookFont.MONO -> FontFamily.Monospace
    else -> null
}

@Composable
private fun Heading(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(top = 20.dp, bottom = 6.dp),
    )
}

@Composable
private fun <T> Choices(
    values: List<T>,
    selected: T,
    label: (T) -> String,
    fontOf: (T) -> FontFamily? = { null },
    onSelected: (T) -> Unit,
) {
    Row(
        modifier = Modifier.horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        values.forEach { value ->
            FilterChip(
                selected = value == selected,
                onClick = { onSelected(value) },
                label = { Text(label(value), fontFamily = fontOf(value)) },
            )
        }
    }
}

@Composable
private fun SliderRow(
    label: String,
    value: Float,
    range: ClosedFloatingPointRange<Float>,
    steps: Int,
    display: String,
    onChange: (Float) -> Unit,
) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 8.dp)) {
        Text(label, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
        Text(display, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary)
    }
    Slider(value = value.coerceIn(range), onValueChange = onChange, valueRange = range, steps = steps)
}

@Composable
private fun SwitchRow(title: String, subtitle: String?, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(vertical = 6.dp)) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            if (subtitle != null) {
                Text(
                    subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        Spacer(Modifier.width(12.dp))
        Switch(checked = checked, onCheckedChange = onChange)
    }
    Spacer(Modifier.height(2.dp))
}
