import 'dart:convert';

import 'package:flutter/painting.dart';

/// How a book is laid out for reading.
enum BookLayout {
  scroll('Scroll by chapter'),
  continuous('Continuous scroll'),
  page('Single page'),
  spread('Two pages');

  final String label;
  const BookLayout(this.label);

  bool get paged => this == page || this == spread;

  static BookLayout parse(String? name) => values.firstWhere(
        (l) => l.name == name,
        orElse: () => BookLayout.scroll,
      );
}

/// How paragraphs are aligned. [book] keeps whatever the book asks for.
enum BookAlign {
  book("Book's own"),
  left('Left'),
  justify('Justified');

  final String label;
  const BookAlign(this.label);

  static BookAlign parse(String? name) => values.firstWhere(
        (a) => a.name == name,
        orElse: () => BookAlign.book,
      );
}

/// The layout and readability options for books, besides the font, its size and
/// the theme, which have settings of their own. Every value is clamped to its
/// range, so a hand-edited or newer preference can't break the reader.
class ReadingStyle {
  static const lineHeightRange = (min: 1.2, max: 2.4);
  static const letterSpacingRange = (min: 0.0, max: 0.2);
  static const wordSpacingRange = (min: 0.0, max: 0.6);
  static const paragraphSpacingRange = (min: 0.0, max: 2.0);
  static const measureRange = (min: 24.0, max: 60.0);

  final BookLayout layout;

  /// Line height, as a multiple of the font size.
  final double lineHeight;

  /// Extra space between letters and between words, in ems.
  final double letterSpacing;
  final double wordSpacing;

  /// Space after each paragraph, in ems. 0 leaves the book's own spacing.
  final double paragraphSpacing;

  /// The widest a line gets, in ems of the reading font.
  final double measure;

  final BookAlign align;

  /// Sets all text in bold.
  final bool bold;

  /// Animates page turns. Off, pages change at once.
  final bool animations;

  /// Shows a reading ruler: a band around the line being read, with the rest
  /// of the page dimmed.
  final bool ruler;

  const ReadingStyle({
    this.layout = BookLayout.scroll,
    this.lineHeight = 1.6,
    this.letterSpacing = 0,
    this.wordSpacing = 0,
    this.paragraphSpacing = 0,
    this.measure = 36,
    this.align = BookAlign.book,
    this.bold = false,
    this.animations = true,
    this.ruler = false,
  });

  ReadingStyle copyWith({
    BookLayout? layout,
    double? lineHeight,
    double? letterSpacing,
    double? wordSpacing,
    double? paragraphSpacing,
    double? measure,
    BookAlign? align,
    bool? bold,
    bool? animations,
    bool? ruler,
  }) =>
      ReadingStyle(
        layout: layout ?? this.layout,
        lineHeight: _clamp(lineHeight ?? this.lineHeight, lineHeightRange),
        letterSpacing:
            _clamp(letterSpacing ?? this.letterSpacing, letterSpacingRange),
        wordSpacing: _clamp(wordSpacing ?? this.wordSpacing, wordSpacingRange),
        paragraphSpacing: _clamp(
            paragraphSpacing ?? this.paragraphSpacing, paragraphSpacingRange),
        measure: _clamp(measure ?? this.measure, measureRange),
        align: align ?? this.align,
        bold: bold ?? this.bold,
        animations: animations ?? this.animations,
        ruler: ruler ?? this.ruler,
      );

  static double _clamp(double v, ({double min, double max}) range) =>
      v.isFinite ? v.clamp(range.min, range.max) : range.min;

  String toJson() => jsonEncode({
        'layout': layout.name,
        'lineHeight': lineHeight,
        'letterSpacing': letterSpacing,
        'wordSpacing': wordSpacing,
        'paragraphSpacing': paragraphSpacing,
        'measure': measure,
        'align': align.name,
        'bold': bold,
        'animations': animations,
        'ruler': ruler,
      });

  /// Anything missing or unreadable takes its default.
  factory ReadingStyle.fromJson(String? json) {
    const defaults = ReadingStyle();
    Map<String, dynamic> map;
    try {
      map = json == null ? const {} : jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      map = const {};
    }
    double? number(String key) => (map[key] as num?)?.toDouble();
    bool? flag(String key) => map[key] is bool ? map[key] as bool : null;
    return defaults.copyWith(
      layout: BookLayout.parse(map['layout'] as String?),
      lineHeight: number('lineHeight'),
      letterSpacing: number('letterSpacing'),
      wordSpacing: number('wordSpacing'),
      paragraphSpacing: number('paragraphSpacing'),
      measure: number('measure'),
      align: BookAlign.parse(map['align'] as String?),
      bold: flag('bold'),
      animations: flag('animations'),
      ruler: flag('ruler'),
    );
  }

  /// The reading text style: spacing and weight on top of [base], whose font
  /// size the spacing is measured against.
  TextStyle applyTo(TextStyle base) {
    final size = base.fontSize ?? 16;
    return base.copyWith(
      height: lineHeight,
      letterSpacing: letterSpacing == 0 ? null : letterSpacing * size,
      wordSpacing: wordSpacing == 0 ? null : wordSpacing * size,
      fontWeight: bold ? FontWeight.w700 : null,
    );
  }

  /// Styles to lay over the book's own for an element. Alignment only touches
  /// text the book doesn't deliberately centre or right-align, such as title
  /// pages and epigraphs.
  Map<String, String> overridesFor(String tag, Map<String, String> bookStyles) {
    const textBlocks = {'p', 'li', 'blockquote', 'dd'};
    if (!textBlocks.contains(tag)) return const {};
    final result = <String, String>{};
    final bookAlign = bookStyles['text-align'];
    final deliberate = bookAlign == 'center' || bookAlign == 'right';
    if (align != BookAlign.book && !deliberate) {
      result['text-align'] = align == BookAlign.justify ? 'justify' : 'left';
    }
    if (paragraphSpacing > 0 && tag == 'p') {
      result['margin-bottom'] = '${paragraphSpacing}em';
    }
    return result;
  }

  @override
  bool operator ==(Object other) =>
      other is ReadingStyle && other.toJson() == toJson();

  @override
  int get hashCode => toJson().hashCode;
}
