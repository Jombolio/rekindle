import 'package:flutter/rendering.dart';

/// Something on a laid-out chapter that a page break mustn't cut through: a
/// line of text, or a whole image. [top] and [bottom] are measured from the top
/// of the chapter.
typedef PageUnit = ({double top, double bottom});

/// Where each page of a chapter starts and ends, as distances from its top.
class PageBreaks {
  final List<double> starts;
  final List<double> ends;
  final double height;

  const PageBreaks._(this.starts, this.ends, this.height);

  int get count => starts.length;

  /// Splits a chapter [height] tall into pages at most [pageHeight] tall. Each
  /// page ends after the last [units] that fits whole, and the next starts at
  /// the first that didn't, so no line is cut in half. A unit taller than a
  /// page, such as a big image, is cut where the page ends.
  factory PageBreaks.compute(
    List<PageUnit> units,
    double height,
    double pageHeight,
  ) {
    if (pageHeight <= 0 || height <= 0) {
      return const PageBreaks._([0], [0], 0);
    }
    final sorted = [...units]..sort((a, b) => a.top.compareTo(b.top));
    final starts = <double>[];
    final ends = <double>[];
    var start = 0.0;
    // Tolerates rounding where one line's bottom meets the next one's top.
    const epsilon = 0.5;

    while (start < height - epsilon) {
      final limit = start + pageHeight;
      var end = start;
      double? next;
      for (final unit in sorted) {
        if (unit.bottom <= start + epsilon) continue;
        if (unit.bottom <= limit + epsilon && unit.top >= start - epsilon) {
          if (unit.bottom > end) end = unit.bottom;
        } else if (unit.top >= start - epsilon) {
          // The first unit that doesn't fit begins the next page.
          next = next == null || unit.top < next ? unit.top : next;
        }
      }
      if (next != null && next < end) {
        // Units overlap (side-by-side boxes): don't cut through the one that
        // spills over, start the next page at it.
        end = next;
      }
      if (end <= start + epsilon) {
        // Nothing fits whole: a unit taller than the page. Cut it at the limit.
        end = limit < height ? limit : height;
        next = end;
      }
      starts.add(start);
      ends.add(end);
      final following = next ?? end;
      if (following >= height - epsilon) break;
      start = following > start + epsilon ? following : end;
    }
    if (starts.isEmpty) {
      starts.add(0);
      ends.add(height);
    }
    return PageBreaks._(starts, ends, height);
  }

  /// The page holding the spot [fraction] of the way through the chapter.
  int pageAt(double fraction) {
    final spot = fraction.clamp(0.0, 1.0) * height;
    var page = 0;
    for (var i = 0; i < starts.length; i++) {
      if (starts[i] <= spot + 0.5) page = i;
    }
    return page;
  }

  /// How far through the chapter [page] begins, from 0 to 1.
  double fractionOf(int page) =>
      height <= 0 ? 0 : (starts[page.clamp(0, count - 1)] / height);
}

/// The lines of text and images inside [root], measured from its top.
List<PageUnit> collectPageUnits(RenderBox root) {
  final units = <PageUnit>[];

  void visit(RenderObject node) {
    if (node is RenderParagraph) {
      _addLines(node, root, units);
      return;
    }
    var hasChildren = false;
    node.visitChildren((child) {
      hasChildren = true;
      visit(child);
    });
    if (!hasChildren && node is RenderBox && node.hasSize && node != root) {
      // A leaf that isn't text, such as an image or a rule: kept whole.
      final top = node.localToGlobal(Offset.zero, ancestor: root).dy;
      if (node.size.height > 0) {
        units.add((top: top, bottom: top + node.size.height));
      }
    }
  }

  visit(root);
  return units;
}

void _addLines(RenderParagraph paragraph, RenderBox root, List<PageUnit> out) {
  if (!paragraph.hasSize) return;
  final origin = paragraph.localToGlobal(Offset.zero, ancestor: root).dy;
  final length =
      paragraph.text.toPlainText(includeSemanticsLabels: false).length;
  if (length == 0) return;
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: length),
  );
  if (boxes.isEmpty) {
    out.add((top: origin, bottom: origin + paragraph.size.height));
    return;
  }
  // One line can come back as several boxes, one per styled run: merge boxes
  // that share a line.
  final lines = <PageUnit>[];
  for (final box in boxes) {
    final top = origin + box.top;
    final bottom = origin + box.bottom;
    final i = lines.indexWhere((l) => top < l.bottom && bottom > l.top);
    if (i < 0) {
      lines.add((top: top, bottom: bottom));
    } else {
      final l = lines[i];
      lines[i] = (
        top: top < l.top ? top : l.top,
        bottom: bottom > l.bottom ? bottom : l.bottom,
      );
    }
  }
  out.addAll(lines);
}
