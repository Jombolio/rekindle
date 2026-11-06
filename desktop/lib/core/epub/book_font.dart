import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

/// The typefaces offered for reading. The first four are fonts already on the
/// system. The last three are bundled for readability, under the SIL Open Font
/// License: OpenDyslexic for dyslexia, Atkinson Hyperlegible for low vision, and
/// Lexend for reading fluency.
enum BookFont {
  standard('Default'),
  serif('Serif'),
  sans('Sans-serif'),
  mono('Monospace'),
  openDyslexic('OpenDyslexic'),
  atkinson('Atkinson Hyperlegible'),
  lexend('Lexend');

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
        BookFont.openDyslexic => 'OpenDyslexic',
        BookFont.atkinson => 'AtkinsonHyperlegible',
        BookFont.lexend => 'Lexend',
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

/// The bundled reading fonts' licences, for the app's licence page. The OFL asks
/// for its text to travel with the fonts.
void registerFontLicences() {
  const fonts = {
    'OpenDyslexic': 'assets/fonts/OFL-OpenDyslexic.txt',
    'Atkinson Hyperlegible': 'assets/fonts/OFL-AtkinsonHyperlegible.txt',
    'Lexend': 'assets/fonts/OFL-Lexend.txt',
  };
  LicenseRegistry.addLicense(() async* {
    for (final MapEntry(key: name, value: path) in fonts.entries) {
      yield LicenseEntryWithLineBreaks([name], await rootBundle.loadString(path));
    }
  });
}
