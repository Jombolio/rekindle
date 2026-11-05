import 'dart:io';

import 'package:flutter/painting.dart';

/// The typefaces offered for reading. Each is a font already on the system, with
/// fallbacks, so choosing one downloads nothing and adds nothing to the app.
enum BookFont {
  standard('Default'),
  serif('Serif'),
  sans('Sans-serif'),
  mono('Monospace');

  final String label;
  const BookFont(this.label);

  /// Prefs store the name, so an unknown value from another version is harmless.
  static BookFont parse(String? name) => BookFont.values.firstWhere(
        (f) => f.name == name,
        orElse: () => BookFont.standard,
      );

  BookFont get next => values[(index + 1) % values.length];

  /// [TextStyle.fontFamily] for this choice. Windows has no generic font names,
  /// while Linux resolves them through fontconfig to whatever the user prefers.
  String? familyFor({required bool isWindows}) => switch (this) {
        BookFont.standard => null,
        BookFont.serif => isWindows ? 'Georgia' : 'serif',
        BookFont.sans => isWindows ? 'Segoe UI' : 'sans-serif',
        BookFont.mono => isWindows ? 'Consolas' : 'monospace',
      };

  /// Applies this choice to a reading style.
  TextStyle applyTo(TextStyle style) {
    final family = familyFor(isWindows: Platform.isWindows);
    return family == null ? style : style.copyWith(fontFamily: family);
  }
}

const double kDefaultBookFontSize = 16;
const double kMinBookFontSize = 10;
const double kMaxBookFontSize = 32;
