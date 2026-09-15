import 'package:flutter_test/flutter_test.dart';
import 'package:rekindle/core/utils/slides.dart';

void main() {
  group('buildSlides', () {
    test('returns nothing when there are no pages', () {
      expect(buildSlides(0, const []), isEmpty);
    });

    test('keeps the cover on its own slide', () {
      // Page 0 is the cover: pairing it with page 1 would offset every spread
      // in the book by one, which is the whole reason for this rule.
      expect(
        buildSlides(5, const [false, false, false, false, false]),
        [
          [0],
          [1, 2],
          [3, 4],
        ],
      );
    });

    test('gives a landscape page a slide to itself', () {
      expect(
        buildSlides(5, const [false, false, true, false, false]),
        [
          [0], // cover
          [1], // would pair with 2, but 2 is a spread
          [2], // the spread itself
          [3, 4],
        ],
      );
    });

    test('does not pair the page before a spread', () {
      // The interesting case: page 1 is portrait and page 2 is portrait too,
      // so they pair — but move the spread and page 1 must stand alone.
      expect(buildSlides(4, const [false, false, false, false]), [
        [0],
        [1, 2],
        [3],
      ]);
      expect(buildSlides(4, const [false, false, true, false]), [
        [0],
        [1],
        [2],
        [3],
      ]);
    });

    test('leaves a trailing odd page alone', () {
      expect(buildSlides(4, const [false, false, false, false]), [
        [0],
        [1, 2],
        [3],
      ]);
    });

    test('treats consecutive spreads as separate slides', () {
      expect(buildSlides(4, const [false, true, true, false]), [
        [0],
        [1],
        [2],
        [3],
      ]);
    });

    test('treats missing spread data as portrait', () {
      // The spread map arrives from the server after the page count when a
      // chapter opens from a local manifest, so buildSlides runs at least once
      // with a short — or empty — list and must not go out of range.
      expect(buildSlides(4, const []), [
        [0],
        [1, 2],
        [3],
      ]);
      expect(buildSlides(4, const [false, false]), [
        [0],
        [1, 2],
        [3],
      ]);
    });

    test('covers every page exactly once, in order', () {
      // Whatever the grouping, no page may be dropped or shown twice.
      for (final spreads in const [
        <bool>[],
        [false, false, false, false, false, false, false],
        [true, false, true, false, true, false, true],
        [false, true, true, false, false, true, false],
      ]) {
        const totalPages = 7;
        final flat = buildSlides(totalPages, spreads).expand((s) => s).toList();
        expect(flat, List.generate(totalPages, (i) => i),
            reason: 'spreads=$spreads');
      }
    });

    test('never puts more than two pages on a slide', () {
      final slides = buildSlides(9, const [false, true, false, false, true]);
      expect(slides.every((s) => s.length <= 2), isTrue);
    });
  });
}
