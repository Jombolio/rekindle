import 'package:flutter/services.dart' show Brightness;
import 'package:flutter_test/flutter_test.dart';
import 'package:rekindle/core/epub/book_theme.dart';

void main() {
  test('"Match app" follows the app into light or dark', () {
    expect(BookTheme.matchApp.resolve(Brightness.light), BookTheme.light);
    expect(BookTheme.matchApp.resolve(Brightness.dark), BookTheme.dark);
  });

  test('a chosen theme ignores the app', () {
    expect(BookTheme.sepia.resolve(Brightness.dark), BookTheme.sepia);
    expect(BookTheme.light.resolve(Brightness.dark), BookTheme.light);
  });

  test('an unknown or missing setting means "Match app"', () {
    expect(BookTheme.parse(null), BookTheme.matchApp);
    expect(BookTheme.parse('midnight'), BookTheme.matchApp);
    expect(BookTheme.parse('sepia'), BookTheme.sepia);
  });

  test('the palette button cycles through the real themes', () {
    expect(BookTheme.light.next, BookTheme.dark);
    expect(BookTheme.dark.next, BookTheme.sepia);
    expect(BookTheme.sepia.next, BookTheme.light);
  });
}
