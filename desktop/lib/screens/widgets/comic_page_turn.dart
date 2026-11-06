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

  /// The back of a sheet, seen where it has folded over mid-turn and nothing
  /// is printed there. A shade up from the [backdrop], so a turning page reads
  /// as paper lifting off the page beneath rather than as a hole cut in it.
  /// A spread never shows it: both sides of that sheet carry a page.
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
/// book reader's page turn ([PageCurlPainter]) over a comic: a fold sweeps
/// from the sheet's free edge to its bound edge, the paper rolling over itself,
/// and the page beneath takes a soft shadow from the roll.
///
/// The sheet that turns is always the lower-numbered slide of the pair the
/// pager sits between, which makes one motion serve both directions: at a
/// progress of 0 it lies flat, and at 1 it has turned right over. Turning
/// forwards runs that 0 to 1 and turning back runs it 1 to 0; because progress
/// is read straight off the pager, a drag curls the sheet under the finger.
///
/// Single pages and spreads are bound differently, as the printing is:
///
/// - A single page is a whole sheet bound at the edge the reader turns away
///   from, with nothing printed on its back.
/// - In a spread the spine is down the middle, and the sheet is the half-page
///   on the leading side of it. It carries two pages, as a real one does: the
///   half being left on its front, and the next slide's facing page on its
///   back, which is how the new page arrives. The other half of the slide
///   being left stays down until the sheet lands on top of it, while the next
///   slide's far page is already showing beyond the sheet's edge.
class ComicPageCurl extends StatefulWidget {
  final PageController controller;

  /// Right to left, as manga reads: a single sheet is bound at its right edge,
  /// and in a spread it is the left half that turns, rightwards over the spine.
  final bool reverse;

  final int slideCount;

  /// Whether the pair starting at this slide turns as a spread, which needs
  /// both it and the slide after it to be two-page ones.
  final bool Function(int leaf) spreadAt;

  /// Builds the slide that turns, by slide index.
  final Widget Function(int index) slideBuilder;

  const ComicPageCurl({
    super.key,
    required this.controller,
    required this.reverse,
    required this.slideCount,
    required this.spreadAt,
    required this.slideBuilder,
  });

  @override
  State<ComicPageCurl> createState() => _ComicPageCurlState();
}

class _ComicPageCurlState extends State<ComicPageCurl> {
  final SnapshotController _snapshot = SnapshotController();
  final _Sheets _sheets = _Sheets();
  late final _CurlPainter _painter = _CurlPainter(_sheets);
  late final _BackPainter _backPainter = _BackPainter(_sheets);

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
    _syncPainter();
  }

  @override
  void didUpdateWidget(ComicPageCurl old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
    }
    _syncPainter();
    if (old.slideCount != widget.slideCount) _onScroll();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    _snapshot.dispose();
    _painter.dispose();
    _backPainter.dispose();
    super.dispose();
  }

  bool get _spread => widget.spreadAt(_leaf);

  void _syncPainter() {
    _painter
      ..reverse = widget.reverse
      ..spread = _spread;
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
      // A different sheet: the rasters held for the last one are no use.
      if (moved) _snapshot.clear();
      setState(() {
        _leaf = leaf ?? _leaf;
        _turning = turning;
      });
      _syncPainter();
    }
    // Rasterise only while a turn is running, so nothing is held at rest.
    _snapshot.allowSnapshotting = turning;
  }

  /// A slide, rasterised at the size it asks for. Loose, so the sheet is the
  /// page as drawn and not the window around it: a single page sizes itself to
  /// the letterboxed rect the pager draws it in, and the curl is of that page.
  /// A spread takes the viewport, which is what two pages side by side fill.
  Widget _sheet(int index, SnapshotPainter painter) => Align(
        child: SnapshotWidget(
          controller: _snapshot,
          // A page is images and text; nothing here blocks rasterising. Fall
          // back to the flat page rather than throwing if that ever changes.
          mode: SnapshotMode.permissive,
          painter: painter,
          child: widget.slideBuilder(index),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (!_spread) {
      return IgnorePointer(child: _sheet(_leaf, _painter));
    }
    return IgnorePointer(
      child: Stack(fit: StackFit.expand, children: [
        // Painted first and only to hand its picture over: in a spread the
        // next slide's facing page is printed on the back of the turning one.
        _sheet(_leaf + 1, _backPainter),
        _sheet(_leaf, _painter),
      ]),
    );
  }
}

/// The picture of the slide being turned to, left by the sheet beneath for the
/// turning sheet above it to print on its back. Both are painted in the same
/// frame, lower one first, so it is never a frame out of date.
class _Sheets {
  ui.Image? back;
}

/// Rasterises the slide being turned to without drawing it: the pager is
/// already showing that slide beneath the overlay.
class _BackPainter extends SnapshotPainter {
  _BackPainter(this._sheets);

  final _Sheets _sheets;

  @override
  void paintSnapshot(PaintingContext context, Offset offset, Size size,
      ui.Image image, Size sourceSize, double pixelRatio) {
    _sheets.back = image;
  }

  @override
  void paint(PaintingContext context, Offset offset, Size size,
      PaintingContextCallback painter) {
    // No raster to hand over; the curl falls back to a plain paper back.
    _sheets.back = null;
  }

  @override
  bool shouldRepaint(_BackPainter oldPainter) => true;
}

/// Draws the snapshotted sheet as a curling page.
///
/// Mutable and shared across frames on purpose: setting [progress] repaints
/// from the raster already taken, which is what keeps a turn cheap.
class _CurlPainter extends SnapshotPainter {
  _CurlPainter(this._sheets);

  final _Sheets _sheets;

  double _progress = 0;
  bool _reverse = false;
  bool _spread = false;

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

  set spread(bool value) {
    if (value == _spread) return;
    _spread = value;
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
    if (_spread) {
      _paintSpread(canvas, image, size);
    } else {
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
    }
    canvas.restore();
  }

  /// A spread turns about the spine down its middle, a half-page at a time.
  void _paintSpread(Canvas canvas, ui.Image front, Size size) {
    final spine = size.width / 2;
    // The half the reader is turning towards. Its page stays down until the
    // turning sheet lands on top of it, so it has to be painted over the next
    // slide, which the pager is already showing beneath the overlay. The other
    // half needs nothing: the next slide's page there is meant to show.
    final staying = _reverse
        ? Rect.fromLTRB(spine, 0, size.width, size.height)
        : Rect.fromLTRB(0, 0, spine, size.height);
    canvas.drawRect(
        staying, Paint()..color = ComicPageTurn.backdrop.withValues(alpha: 1));
    final scaleX = front.width / size.width;
    final scaleY = front.height / size.height;
    canvas.drawImageRect(
      front,
      Rect.fromLTRB(staying.left * scaleX, 0, staying.right * scaleX,
          size.height * scaleY),
      staying,
      Paint()..filterQuality = FilterQuality.medium,
    );
    PageCurlPainter(
      front: front,
      // Both sides of this sheet carry a page, as a printed spread does: the
      // half being left, and the next slide's facing page on the back.
      back: _sheets.back,
      area: size,
      spine: spine,
      direction: _reverse ? -1 : 1,
      width: spine,
      progress: _progress,
      // Only ever seen in the letterbox around the pages, so the reader's own
      // background rather than a paper tone.
      paper: ComicPageTurn.backdrop,
      clip: Offset.zero & size,
    ).paint(canvas, size);
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
