import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rekindle/core/epub/book_font.dart';

void main() {
  test('reads back what was saved, and survives an unknown value', () {
    for (final font in BookFont.values) {
      expect(BookFont.parse(font.name), font);
    }
    expect(BookFont.parse('comic-sans'), BookFont.standard);
    expect(BookFont.parse(null), BookFont.standard);
  });

  test('cycling goes through every font and comes back', () {
    final seen = <BookFont>{};
    var font = BookFont.standard;
    for (var i = 0; i < BookFont.values.length; i++) {
      seen.add(font);
      font = font.next;
    }
    expect(seen, BookFont.values.toSet());
    expect(font, BookFont.standard);
  });

  test('Windows gets real font names, since it has no generic ones', () {
    expect(BookFont.serif.familyFor(isWindows: true), 'Georgia');
    expect(BookFont.serif.familyFor(isWindows: false), 'serif');
    expect(BookFont.standard.familyFor(isWindows: true), isNull);
  });

  test('the default leaves the reading style alone', () {
    const style = TextStyle(fontSize: 20);
    expect(BookFont.standard.applyTo(style), same(style));
    expect(BookFont.mono.applyTo(style).fontSize, 20);
    expect(BookFont.mono.applyTo(style).fontFamily, isNotNull);
  });
}
