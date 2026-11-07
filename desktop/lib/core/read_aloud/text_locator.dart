import 'package:flutter/rendering.dart';

/// Whether [a] and [b] are the same colour, near enough: a colour written as
/// CSS comes back with its alpha rounded.
bool sameColour(Color a, Color b) =>
    (a.r - b.r).abs() < 0.01 &&
    (a.g - b.g).abs() < 0.01 &&
    (a.b - b.b).abs() < 0.01 &&
    (a.a - b.a).abs() < 0.02;

/// The top of the first text inside [root] painted with a [highlight]
/// background, relative to [root]. Null when none is laid out.
double? highlightTop(RenderObject root, Color highlight) {
  double? found;

  void visit(RenderObject node) {
    if (found != null) return;
    if (node is RenderParagraph) {
      final top = _inParagraph(node, root, highlight);
      if (top != null) found = top;
      return;
    }
    node.visitChildren(visit);
  }

  visit(root);
  return found;
}

double? _inParagraph(RenderParagraph paragraph, RenderObject root, Color highlight) {
  if (!paragraph.hasSize) return null;
  int? start, end;
  var offset = 0;
  paragraph.text.visitChildren((span) {
    final length = switch (span) {
      TextSpan(:final text) => text?.length ?? 0,
      PlaceholderSpan() => 1,
      _ => 0,
    };
    final colour = span.style?.background?.color;
    if (length > 0 && colour != null && sameColour(colour, highlight)) {
      start ??= offset;
      end = offset + length;
    }
    offset += length;
    return true;
  });
  if (start == null) return null;
  final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: start!, extentOffset: end!));
  final local = boxes.isEmpty ? 0.0 : boxes.first.top;
  return paragraph.localToGlobal(Offset(0, local), ancestor: root).dy;
}
