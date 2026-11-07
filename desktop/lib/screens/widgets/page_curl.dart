import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// A page curling over like paper, for a page turn.
///
/// The page is hinged at [spine] and reaches [width] from it, towards
/// [direction] (1: to the right, -1: to the left). A fold sweeps from the free
/// edge to the spine as [progress] goes from 0 to 1. Beyond the fold the page
/// wraps round a roll that tightens as it goes, then lies flat again, folded
/// back over itself, showing its [back]. At 1 the whole page has turned over
/// onto the other side of the spine.
///
/// It's drawn in narrow vertical strips, each a slice of the page images moved
/// to where that slice of paper sits on the roll, and shaded by how far it
/// faces away from the light. The page beneath gets a soft shadow from the roll.
class PageCurlPainter extends CustomPainter {
  /// The images hold the whole area, at the screen's pixel ratio.
  final ui.Image front;

  /// What's printed on the back, in its final place across the spine. Plain
  /// paper when null.
  final ui.Image? back;

  /// The area [back] is a picture of, when it isn't the same as [area]: the
  /// back can be a picture of something larger, with this sheet's area lying
  /// at [backOrigin] within it. A comic reader turns a spread whose next
  /// slide may be a different size, so it hands over the whole viewport and
  /// where the sheet sits in it.
  final Size? backArea;
  final Offset backOrigin;
  final Size area;
  final double spine;
  final int direction;
  final double width;
  final double progress;
  final Color paper;
  final Rect? clip;

  static const _strips = 120;

  const PageCurlPainter({
    required this.front,
    this.back,
    required this.area,
    required this.spine,
    required this.direction,
    required this.width,
    required this.progress,
    required this.paper,
    this.clip,
    this.backArea,
    this.backOrigin = Offset.zero,
  });

  /// The band of [back] printed behind the sheet between [left] and [right],
  /// both measured across this sheet's [area].
  Rect _backSrc(ui.Image back, double left, double right) {
    final whole = backArea ?? area;
    final scaleX = back.width / whole.width;
    final scaleY = back.height / whole.height;
    return Rect.fromLTRB(
      (left + backOrigin.dx) * scaleX,
      backOrigin.dy * scaleY,
      (right + backOrigin.dx) * scaleX,
      (backOrigin.dy + area.height) * scaleY,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (width <= 0) return;
    if (clip != null) canvas.clipRect(clip!);

    final t = progress.clamp(0.0, 1.0);
    // Paint the flat endpoints explicitly. In particular, t == 0 is a real
    // frame after capturing the destination, not an empty overlay.
    if (t == 0 || t == 1) {
      final edge = spine + direction * width * (t == 0 ? 1 : -1);
      final rect = Rect.fromLTRB(
          math.min(spine, edge), 0, math.max(spine, edge), size.height);
      canvas.drawRect(rect, Paint()..color = paper.withValues(alpha: 1));
      final image = t == 0 ? front : back;
      if (image != null) {
        canvas.drawImageRect(
          image,
          t == 0
              ? Rect.fromLTRB(
                  rect.left * image.width / area.width,
                  0,
                  rect.right * image.width / area.width,
                  image.height.toDouble())
              : _backSrc(image, rect.left, rect.right),
          rect,
          Paint()..filterQuality = FilterQuality.medium,
        );
      }
      return;
    }

    // The fold moves from the free edge to the spine; the roll tightens as it
    // goes, so the page lies flat at the end.
    final fold = width * (1 - t);
    final radius = width * 0.16 * (1 - t);
    final halfTurn = math.pi * radius;

    // Where paper at distance [u] from the spine ends up, as a distance from
    // the spine, and the angle it has rolled through.
    (double, double) place(double u) {
      final s = u - fold;
      if (s <= 0) return (u, 0);
      final angle = s / radius;
      if (angle <= math.pi) return (fold + radius * math.sin(angle), angle);
      return (fold - (s - halfTurn), math.pi);
    }

    double screen(double d) => spine + direction * d;

    final scaleX = front.width / area.width;
    final scaleY = front.height / area.height;
    final paperPaint = Paint()..color = paper.withValues(alpha: 1);
    final imagePaint = Paint()..filterQuality = FilterQuality.medium;

    // The part before the fold is still flat: one piece, so it has no seams.
    final flatEdge = screen(fold);
    final flat = Rect.fromLTRB(
        math.min(spine, flatEdge), 0, math.max(spine, flatEdge), size.height);
    if (flat.width > 0) {
      canvas.drawRect(flat, paperPaint);
      canvas.drawImageRect(
        front,
        Rect.fromLTRB(
            flat.left * scaleX, 0, flat.right * scaleX, area.height * scaleY),
        flat,
        imagePaint,
      );
    }

    // The rest, in strips: (where it's printed, where it is now, shade).
    final fronts = <(Rect, Rect, double)>[];
    final backs = <(Rect, Rect, double)>[];
    for (var i = 0; i < _strips; i++) {
      final ua = fold + (width - fold) * i / _strips;
      final ub = fold + (width - fold) * (i + 1) / _strips;
      final (pa, aa) = place(ua);
      final (pb, ab) = place(ub);
      final angle = (aa + ab) / 2;
      final xa = screen(pa), xb = screen(pb);
      // Half a pixel of overlap hides the joins between strips.
      final dst = Rect.fromLTRB(
          math.min(xa, xb) - 0.5, 0, math.max(xa, xb) + 0.5, size.height);
      if (dst.width <= 0.6) continue;
      if (angle <= math.pi / 2) {
        // The printed side, still facing up, darker as it turns away.
        final sa = screen(ua), sb = screen(ub);
        final src = Rect.fromLTRB(math.min(sa, sb) * scaleX, 0,
            math.max(sa, sb) * scaleX, area.height * scaleY);
        fronts.add((src, dst, 0.3 * (1 - math.cos(angle))));
      } else {
        // The back, now facing up. With a [back] image, what's printed there
        // where this paper will lie once turned; otherwise the front showing
        // faintly through, reversed.
        final sa = back != null ? spine - direction * ua : screen(ua);
        final sb = back != null ? spine - direction * ub : screen(ub);
        final src = back != null
            ? _backSrc(back!, math.min(sa, sb), math.max(sa, sb))
            : Rect.fromLTRB(math.min(sa, sb) * scaleX, 0,
                math.max(sa, sb) * scaleX, area.height * scaleY);
        // Lit at the top of the roll, settling as it lies flat.
        final shade = (0.16 * (1 + math.cos(angle)) + 0.04) * (1 - t);
        backs.add((src, dst, shade));
      }
    }

    // Each set is painted paper first, then print, then shade, so no strip's
    // paper covers its neighbour's edge.
    void draw(List<(Rect, Rect, double)> strips, {required bool isBack}) {
      for (final (_, dst, _) in strips) {
        canvas.drawRect(dst, paperPaint);
      }
      for (final (src, dst, _) in strips) {
        if (!isBack) {
          canvas.drawImageRect(front, src, dst, imagePaint);
        } else if (back != null) {
          canvas.drawImageRect(back!, src, dst, imagePaint);
        } else {
          // Show-through: the front, mirrored and faint.
          canvas.save();
          canvas.translate(dst.center.dx, 0);
          canvas.scale(-1, 1);
          canvas.translate(-dst.center.dx, 0);
          canvas.drawImageRect(
              front,
              src,
              dst,
              Paint()
                ..filterQuality = FilterQuality.medium
                ..color = const Color.fromRGBO(0, 0, 0, 0.1));
          canvas.restore();
        }
      }
      // Shade at each strip's exact width: overlapping shade would show as
      // darker lines at the joins.
      for (final (_, dst, shade) in strips) {
        if (shade > 0.002) {
          canvas.drawRect(dst.deflate(0.5),
              Paint()..color = Color.fromRGBO(0, 0, 0, shade.clamp(0.0, 0.6)));
        }
      }
    }

    draw(fronts, isBack: false);

    // The roll's shadow on the page beneath, just past its outer edge.
    final edge = screen(fold + radius);
    const reach = 36.0;
    final shadowRect = Rect.fromLTRB(
      direction > 0 ? edge : edge - reach,
      0,
      direction > 0 ? edge + reach : edge,
      size.height,
    );
    final strength = 0.22 * math.sin(math.pi * t);
    if (strength > 0.01) {
      canvas.drawRect(
        shadowRect,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(edge, 0),
            Offset(edge + direction * reach, 0),
            [
              Color.fromRGBO(0, 0, 0, strength),
              const Color.fromRGBO(0, 0, 0, 0)
            ],
          ),
      );
    }

    draw(backs, isBack: true);
  }

  @override
  bool shouldRepaint(PageCurlPainter old) =>
      old.progress != progress ||
      !identical(old.front, front) ||
      !identical(old.back, back) ||
      old.spine != spine ||
      old.width != width ||
      old.area != area ||
      old.direction != direction ||
      old.paper != paper ||
      old.clip != clip ||
      old.backArea != backArea ||
      old.backOrigin != backOrigin;
}
