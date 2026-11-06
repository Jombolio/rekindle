import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show Brightness;

/// The colours books are read in. [matchApp] is only a setting: it resolves to
/// [light] or [dark] when a book opens.
enum BookTheme {
  matchApp('Match app'),
  light('Light'),
  dark('Dark'),
  sepia('Sepia');

  final String label;
  const BookTheme(this.label);

  /// Prefs store the name, so an unknown value from another version is harmless.
  static BookTheme parse(String? name) => BookTheme.values.firstWhere(
        (t) => t.name == name,
        orElse: () => BookTheme.matchApp,
      );

  /// The theme to read in, given how bright the app itself is.
  BookTheme resolve(Brightness appBrightness) => this == matchApp
      ? (appBrightness == Brightness.dark ? dark : light)
      : this;

  /// The next theme the reader's palette button moves to.
  BookTheme get next => switch (this) {
        light || matchApp => dark,
        dark => sepia,
        sepia => light,
      };

  Color get background => switch (this) {
        dark => const Color(0xFF1A1A1A),
        sepia => const Color(0xFFF5ECD7),
        light || matchApp => const Color(0xFFFFFFFF),
      };

  Color get foreground => switch (this) {
        dark => const Color(0xFFE0E0E0),
        sepia => const Color(0xFF3B2C1A),
        light || matchApp => const Color(0xDD000000),
      };
}
