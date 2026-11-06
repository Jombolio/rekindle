import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'page_curl.dart';

/// The pager's position in slides, safe to read before it has laid out.
double comicPagerPage(PageController controller) =>
    controller.hasClients && controller.position.hasContentDimensions
        ? controller.page ?? controller.initialPage.toDouble()
        : controller.initialPage.toDouble();

/// One slide of the comic pager, held still in the viewport.
///
/// A pager slides its pages sideways; a book doesn't. Each slide cancels that
/// translation so it stays put, and the sheet being turned is drawn curling
/// over the top by [ComicPageCurl]. Slides a whole page away draw nothing, so
/// at rest only the slide being read shows, and during a turn only the slide
/// being turned to — which the curling sheet covers until the turn uncovers it.
class ComicPageTurn extends StatelessWidget {
  final PageController controller;
  final int index;

  /// Right to left, as manga reads. The pager is reversed, so its translation
  /// is too.
  final bool reverse;

  final Widget child;

  const ComicPageTurn({
    super.key,
    required this.controller,
    required this.index,
    required this.reverse,
    required this.child,
  });

  /// The reader's own background, behind every slide.
  static const Color backdrop = Colors.black;

  /// The back of a sheet, seen where it has folded over mid-turn. A shade up
  /// from the [backdrop], so a turning page reads as paper lifting off the
  /// page beneath rather than as a hole cut in it.
  static const Color paper = Color(0xFF2B2B2B);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => AnimatedBuilder(
          animation: controller,
          child: RepaintBoundary(child: child),
          builder: (context, child) {
            final offset =
                (comicPagerPage(controller) - index).clamp(-1.0, 1.0);
            if (offset.abs() >= 1) return const SizedBox.expand();
            return Transform.translate(
              offset: Offset(
                  (reverse ? -offset : offset) * constraints.maxWidth, 0),
              // Opaque, so the slide being turned to hides the one behind it.
              child: Stack(fit: StackFit.expand, children: [
                const ColoredBox(color: backdrop),
                child!,
              ]),
            );
          },
        ),
      );
}

/// The sheet being turned, curling over the pager like paper.
///
/// Sits above the pager, so the sheet lies over the slide being turned to,
/// which the pager holds still beneath it (see [ComicPageTurn]). This is the
/// book reader's page turn ([PageCurlPainter]) over a comic: a fold sweeps from
/// the sheet's free edge to its bound edge, the paper rolling over itself and
/// showing its back, and the slide beneath takes a soft shadow from the roll.
///
/// The sheet that turns is always the lower-numbered slide of the pair the
/// pager sits between, which makes one motion serve both directions: at a
/// progress of 0 it lies flat over the next slide, and at 1 it has turned right
/// over and off the far edge. Turning forwards runs that 0 to 1 and turning
/// back runs it 1 to 0; because progress is read straight off the pager, a drag
/// curls the sheet under the reader's finger.
class ComicPageCurl extends StatefulWidget {
  final PageController controller;

  /// Right to left, as manga reads: the sheet is bound at its right edge and
  /// turns rightwards, rather than bound left and turning leftwards.
  final bool reverse;

  final int slideCount;

  /// Builds the slide that turns, by slide index.
  final Widget Function(int index) slideBuilder;

  const ComicPageCurl({
    super.key,
    required this.controller,
    required this.reverse,
    required this.slideCount,
    required this.slideBuilder,
  });

  @override
  State<ComicPageCurl> createState() => _ComicPageCurlState();
}

class _ComicPageCurlState extends State<ComicPageCurl> {
  final SnapshotController _snapshot = SnapshotController();
  final _CurlPainter _painter = _CurlPainter();

  /// The slide being turned: the lower-numbered one of the pair the pager sits
  /// between. Kept built even at rest, so the sheet's image is ready to
  /// rasterise the moment a turn starts.
  int _leaf = 0;
  bool _turning = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
    _leaf = _leafFor(comicPagerPage(widget.controller)) ?? 0;
    _painter.reverse = widget.reverse;
  }

  @override
  void didUpdateWidget(ComicPageCurl old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
    }
    _painter.reverse = widget.reverse;
    if (old.slideCount != widget.slideCount) _onScroll();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    _snapshot.dispose();
    _painter.dispose();
    super.dispose();
  }

  /// The pair the pager sits between, named by its lower slide. Null when
  /// there is nothing to turn.
  int? _leafFor(double page) {
    final last = widget.slideCount - 2;
    return last < 0 ? null : page.floor().clamp(0, last);
  }

  void _onScroll() {
    if (!mounted) return;
    final page = comicPagerPage(widget.controller);
    final leaf = _leafFor(page);
    final progress = leaf == null ? 0.0 : (page - leaf).clamp(0.0, 1.0);
    // Repaints the curl without rebuilding, reusing the sheet's raster.
    _painter.progress = progress;
    final turning = progress > 0 && progress < 1;
    final moved = leaf != null && leaf != _leaf;
    if (moved || turning != _turning) {
      // A different sheet: the raster held for the last one is no use.
      if (moved) _snapshot.clear();
      setState(() {
        _leaf = leaf ?? _leaf;
        _turning = turning;
      });
    }
    // Rasterise only while a turn is running, so nothing is held at rest.
    _snapshot.allowSnapshotting = turning;
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        // Loose, so the sheet is the page as drawn and not the window around
        // it: a page sizes itself to the letterboxed rect the pager draws it
        // in, and the curl is of that page, roll and all. Centred, where the
        // pager puts it.
        child: Align(
          child: SnapshotWidget(
            controller: _snapshot,
            // A page is images and text; nothing here blocks rasterising.
            // Fall back to the flat page rather than throwing if that ever
            // changes.
            mode: SnapshotMode.permissive,
            painter: _painter,
            child: widget.slideBuilder(_leaf),
          ),
        ),
      );
}

/// Draws the snapshotted sheet as a curling page.
///
/// Mutable and shared across frames on purpose: setting [progress] repaints
/// from the raster already taken, which is what keeps a turn cheap.
class _CurlPainter extends SnapshotPainter {
  double _progress = 0;
  bool _reverse = false;

  set progress(double value) {
    if (value == _progress) return;
    _progress = value;
    notifyListeners();
  }

  set reverse(bool value) {
    if (value == _reverse) return;
    _reverse = value;
    notifyListeners();
  }

  /// Flat: the pager is already showing this slide itself.
  bool get _flat => _progress <= 0 || _progress >= 1;

  @override
  void paintSnapshot(PaintingContext context, Offset offset, Size size,
      ui.Image image, Size sourceSize, double pixelRatio) {
    if (_flat) return;
    final canvas = context.canvas;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    PageCurlPainter(
      front: image,
      area: size,
      // Bound at the edge the reader turns away from, reaching across the
      // page to the free edge it is lifted by.
      spine: _reverse ? size.width : 0,
      direction: _reverse ? -1 : 1,
      width: size.width,
      progress: _progress,
      paper: ComicPageTurn.paper,
      // Paper that has turned right over lands past the bound edge, where
      // there is no page any more: clipped off, as the book clips it to the
      // page rather than letting it run into the margin.
      clip: Offset.zero & size,
    ).paint(canvas, size);
    canvas.restore();
  }

  @override
  void paint(PaintingContext context, Offset offset, Size size,
      PaintingContextCallback painter) {
    // Reached with no raster to curl: at rest, where the pager already shows
    // the page, or if the sheet could not be rasterised. Mid-turn, show it
    // flat rather than leaving a gap.
    if (_flat) return;
    painter(context, offset);
  }

  @override
  bool shouldRepaint(_CurlPainter oldPainter) => true;
}
