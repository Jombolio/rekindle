import 'package:flutter_test/flutter_test.dart';
import 'package:rekindle/core/epub/page_breaks.dart';

/// [count] lines [height] tall, one after another from [from].
List<PageUnit> lines(int count, {double height = 20, double from = 0}) => [
      for (var i = 0; i < count; i++)
        (top: from + i * height, bottom: from + (i + 1) * height),
    ];

void main() {
  test('pages end on whole lines', () {
    // 10 lines of 20, pages of 50: two lines a page, never two and a half.
    final breaks = PageBreaks.compute(lines(10), 200, 50);
    expect(breaks.starts, [0, 40, 80, 120, 160]);
    expect(breaks.ends, [40, 80, 120, 160, 200]);
  });

  test('a chapter shorter than a page is one page', () {
    final breaks = PageBreaks.compute(lines(2), 40, 500);
    expect(breaks.count, 1);
    expect(breaks.ends.single, 40);
  });

  test('the gap between paragraphs starts no page', () {
    // Two lines, a 30 gap, two more lines. The second page starts at the third
    // line, not in the gap.
    final units = [...lines(2), ...lines(2, from: 70)];
    final breaks = PageBreaks.compute(units, 110, 60);
    expect(breaks.starts, [0, 70]);
  });

  test('an image taller than a page is cut where the page ends', () {
    final units = [
      ...lines(1),
      (top: 20.0, bottom: 320.0),
      ...lines(1, from: 320),
    ];
    final breaks = PageBreaks.compute(units, 340, 100);
    expect(breaks.starts.first, 0);
    // Every page moves on, and the whole chapter is covered.
    for (var i = 1; i < breaks.count; i++) {
      expect(breaks.starts[i], greaterThan(breaks.starts[i - 1]));
    }
    expect(breaks.ends.last, 340);
  });

  test('finds the page for a saved position and back', () {
    final breaks = PageBreaks.compute(lines(10), 200, 50);
    expect(breaks.pageAt(0), 0);
    expect(breaks.pageAt(0.5), 2); // 100 lies on the page starting at 80.
    expect(breaks.pageAt(1), 4);
    expect(breaks.fractionOf(2), 0.4);
  });

  test('nothing to lay out still gives a page', () {
    expect(PageBreaks.compute(const [], 0, 100).count, 1);
  });
}
