import 'package:flutter_test/flutter_test.dart';
import 'package:rekindle/core/utils/natural_sort.dart';

/// Convenience: sort a copy so each test reads as the ordering it asserts.
List<String> sorted(List<String> input) =>
    [...input]..sort(naturalCompare);

void main() {
  group('naturalCompare', () {
    test('orders numbers by value, not by digit', () {
      // The reason this function exists: a plain string sort puts "Chapter 10"
      // before "Chapter 2".
      expect(
        sorted(['Chapter 10', 'Chapter 2', 'Chapter 1']),
        ['Chapter 1', 'Chapter 2', 'Chapter 10'],
      );
    });

    test('compares numbers by value, breaking ties on length', () {
      // "007" and "7" are the same number, so neither wins on value. The
      // function then falls back to comparing lengths rather than reporting
      // them equal, which keeps the order of two differently-named files
      // deterministic instead of dependent on the sort's input order.
      expect(naturalCompare('Page 007', 'Page 7'), greaterThan(0));
      expect(naturalCompare('Page 7', 'Page 007'), lessThan(0));

      // Value still decides when the numbers actually differ, whatever the
      // digit count.
      expect(
        sorted(['Page 010', 'Page 9']),
        ['Page 9', 'Page 010'],
      );
    });

    test('is case-insensitive', () {
      expect(naturalCompare('Apple', 'apple'), 0);
      expect(
        sorted(['banana', 'Apple', 'cherry']),
        ['Apple', 'banana', 'cherry'],
      );
    });

    test('handles several number runs in one name', () {
      expect(
        sorted(['v1 c10', 'v1 c2', 'v10 c1', 'v2 c1']),
        ['v1 c2', 'v1 c10', 'v2 c1', 'v10 c1'],
      );
    });

    test('treats a shorter name as coming first when it is a prefix', () {
      expect(naturalCompare('file1', 'file1a'), lessThan(0));
      expect(naturalCompare('file1a', 'file1'), greaterThan(0));
    });

    test('returns zero for identical strings', () {
      expect(naturalCompare('Chapter 3.cbz', 'Chapter 3.cbz'), 0);
    });

    test('sorts realistic archive filenames', () {
      expect(
        sorted([
          'Chapter 11.cbz',
          'Chapter 2.cbz',
          'Chapter 1.cbz',
          'Chapter 20.cbz',
          'Chapter 3.cbz',
        ]),
        [
          'Chapter 1.cbz',
          'Chapter 2.cbz',
          'Chapter 3.cbz',
          'Chapter 11.cbz',
          'Chapter 20.cbz',
        ],
      );
    });

    test('is a consistent ordering', () {
      // Whatever the rules, comparing in both directions must agree, or a sort
      // built on this can produce a different result depending on input order.
      const names = ['a1', 'A1', 'a2', 'a10', 'b1', 'a1b', 'a'];
      for (final x in names) {
        for (final y in names) {
          final ab = naturalCompare(x, y);
          final ba = naturalCompare(y, x);
          expect(ab.sign, -ba.sign, reason: 'compare("$x","$y") vs reverse');
        }
      }
    });
  });
}
