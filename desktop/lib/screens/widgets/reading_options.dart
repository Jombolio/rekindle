import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/epub/book_font.dart';
import '../../core/epub/book_theme.dart';
import '../../core/epub/reading_style.dart';
import '../../core/read_aloud/voices.dart';
import '../../providers/read_aloud_provider.dart';
import '../../providers/settings_provider.dart';

/// Every reading option for books: layout, font, size, theme, spacing, line
/// width, alignment, bold text, page-turn animation and the reading ruler. Used
/// in Settings and in the reader's options panel, and changes apply at once.
class ReadingOptionsForm extends ConsumerWidget {
  /// Called after a theme is picked here. The reader uses it to drop a theme
  /// chosen with its palette button, so the pick shows straight away.
  final VoidCallback? onThemePicked;

  const ReadingOptionsForm({super.key, this.onThemePicked});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final style = settings.readingStyle;
    final theme = Theme.of(context);
    void update(ReadingStyle next) => notifier.setReadingStyle(next);

    String ems(double v) => v == 0 ? 'None' : '${v.toStringAsFixed(2)} em';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Heading('Layout'),
        _Choices<BookLayout>(
          values: BookLayout.values,
          selected: style.layout,
          label: (l) => l.label,
          onSelected: (l) => update(style.copyWith(layout: l)),
        ),
        const _Heading('Font'),
        DropdownButton<BookFont>(
          value: settings.bookFont,
          isExpanded: true,
          items: [
            for (final font in BookFont.values)
              DropdownMenuItem(
                value: font,
                // Each name in its own typeface, to choose by eye.
                child: Text(
                  font.label,
                  style: TextStyle(
                    fontFamily: font.familyFor(isWindows: Platform.isWindows),
                  ),
                ),
              ),
          ],
          onChanged: (font) {
            if (font != null) notifier.setBookFont(font);
          },
        ),
        _SliderRow(
          label: 'Text size',
          value: settings.bookFontSize,
          min: kMinBookFontSize,
          max: kMaxBookFontSize,
          divisions: (kMaxBookFontSize - kMinBookFontSize).round(),
          display: settings.bookFontSize.round().toString(),
          onChanged: (v) => notifier.setBookFontSize(v.roundToDouble()),
        ),
        const _Heading('Theme'),
        _Choices<BookTheme>(
          values: BookTheme.values,
          selected: settings.bookTheme,
          label: (t) => t.label,
          onSelected: (t) {
            notifier.setBookTheme(t);
            onThemePicked?.call();
          },
        ),
        const _Heading('Spacing'),
        _SliderRow(
          label: 'Line spacing',
          value: style.lineHeight,
          min: ReadingStyle.lineHeightRange.min,
          max: ReadingStyle.lineHeightRange.max,
          divisions: 12,
          display: '${style.lineHeight.toStringAsFixed(1)}×',
          onChanged: (v) => update(style.copyWith(lineHeight: v)),
        ),
        _SliderRow(
          label: 'Letter spacing',
          value: style.letterSpacing,
          min: ReadingStyle.letterSpacingRange.min,
          max: ReadingStyle.letterSpacingRange.max,
          divisions: 8,
          display: ems(style.letterSpacing),
          onChanged: (v) => update(style.copyWith(letterSpacing: v)),
        ),
        _SliderRow(
          label: 'Word spacing',
          value: style.wordSpacing,
          min: ReadingStyle.wordSpacingRange.min,
          max: ReadingStyle.wordSpacingRange.max,
          divisions: 12,
          display: ems(style.wordSpacing),
          onChanged: (v) => update(style.copyWith(wordSpacing: v)),
        ),
        _SliderRow(
          label: 'Paragraph spacing',
          value: style.paragraphSpacing,
          min: ReadingStyle.paragraphSpacingRange.min,
          max: ReadingStyle.paragraphSpacingRange.max,
          divisions: 8,
          display: style.paragraphSpacing == 0
              ? "Book's own"
              : '${style.paragraphSpacing.toStringAsFixed(2)} em',
          onChanged: (v) => update(style.copyWith(paragraphSpacing: v)),
        ),
        const _Heading('Page'),
        _SliderRow(
          label: 'Line width',
          value: style.measure,
          min: ReadingStyle.measureRange.min,
          max: ReadingStyle.measureRange.max,
          divisions: 18,
          // An em holds about two characters of running text.
          display: '~${(style.measure * 2).round()} characters',
          onChanged: (v) => update(style.copyWith(measure: v.roundToDouble())),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('Alignment', style: theme.textTheme.bodyMedium),
        ),
        _Choices<BookAlign>(
          values: BookAlign.values,
          selected: style.align,
          label: (a) => a.label,
          onSelected: (a) => update(style.copyWith(align: a)),
        ),
        const _Heading('Accessibility'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Bold text'),
          value: style.bold,
          onChanged: (v) => update(style.copyWith(bold: v)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Page-turn animation'),
          subtitle: const Text('Off, pages change at once.'),
          value: style.animations,
          onChanged: (v) => update(style.copyWith(animations: v)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Reading ruler'),
          subtitle: const Text(
              'Highlights the lines under the pointer and dims the rest.'),
          value: style.ruler,
          onChanged: (v) => update(style.copyWith(ruler: v)),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.restart_alt),
            label: const Text('Reset layout and spacing'),
            onPressed: () => update(ReadingStyle(layout: style.layout)),
          ),
        ),
      ],
    );
  }
}

/// The reader's options panel: the form, in a drawer beside the book.
class ReadingOptionsPanel extends StatelessWidget {
  final VoidCallback? onThemePicked;

  const ReadingOptionsPanel({super.key, this.onThemePicked});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text('Reading options',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _ReadAloudVoice(),
                  ReadingOptionsForm(onThemePicked: onThemePicked),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The voice books are read aloud in. Changing it while reading carries on
/// from the same sentence in the new voice.
class _ReadAloudVoice extends ConsumerWidget {
  const _ReadAloudVoice();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pack = ref.watch(voicePackProvider);
    final voice = ref.watch(readAloudVoiceProvider);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Heading('Read-aloud voice'),
        if (pack.installed)
          _Choices<KokoroVoice>(
            values: kokoroVoices,
            selected: voice,
            label: (v) => v.label.split(' · ').first,
            onSelected: (v) =>
                ref.read(readAloudVoiceProvider.notifier).select(v),
          )
        else
          Text(
            pack.downloading
                ? 'The voice is downloading in Settings.'
                : 'Download the voice in Settings, under Books.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
      ],
    );
  }
}

/// Dims the page except for a band around [y], to keep the eye on one line.
class ReadingRulerPainter extends CustomPainter {
  final double? y;
  final double band;
  final Color shade;
  final Color edge;

  const ReadingRulerPainter({
    required this.y,
    required this.band,
    required this.shade,
    required this.edge,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centre = y ?? size.height / 2;
    final top = (centre - band / 2).clamp(0.0, size.height);
    final bottom = (centre + band / 2).clamp(0.0, size.height);
    final dim = Paint()..color = shade.withValues(alpha: 0.6);
    canvas.drawRect(Rect.fromLTRB(0, 0, size.width, top), dim);
    canvas.drawRect(Rect.fromLTRB(0, bottom, size.width, size.height), dim);
    final line = Paint()
      ..color = edge.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, top), Offset(size.width, top), line);
    canvas.drawLine(Offset(0, bottom), Offset(size.width, bottom), line);
  }

  @override
  bool shouldRepaint(ReadingRulerPainter old) =>
      old.y != y || old.band != band || old.shade != shade || old.edge != edge;
}

class _Heading extends StatelessWidget {
  final String text;
  const _Heading(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 6),
      child: Text(
        text,
        style: theme.textTheme.labelLarge
            ?.copyWith(color: theme.colorScheme.primary),
      ),
    );
  }
}

class _Choices<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onSelected;

  const _Choices({
    required this.values,
    required this.selected,
    required this.label,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final value in values)
          ChoiceChip(
            label: Text(label(value)),
            selected: value == selected,
            onSelected: (_) => onSelected(value),
          ),
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
              Text(
                display,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.primary),
              ),
            ],
          ),
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          label: display,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
