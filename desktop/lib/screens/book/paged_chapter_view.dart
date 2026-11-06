import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../core/epub/page_breaks.dart';

/// Where a paged chapter is, for the reader to show and save. In a spread,
/// [page] is the left-hand page, which is -1 on a chapter's opening spread,
/// where the first page sits alone on the right.
typedef PagePosition = ({int page, int count, double fraction});

/// One chapter shown a page, or a two-page spread, at a time, like a book.
///
/// The chapter is laid out once at the column's width, and each page is a
/// window onto it, cut between lines (see [PageBreaks]). Turning a page only
/// moves the window, so it costs no rebuild.
///
/// Spreads pair pages as a printed book does: a chapter opens on a right-hand
/// page, then 2–3, 4–5 and so on. Pages turn like paper: in a spread, the
/// right-hand page folds over the spine onto the left, showing the next page on
/// its back; a single page lifts away from its left edge.
class PagedChapterView extends StatefulWidget {
  /// The whole chapter. Shown once per visible page.
  final Widget content;

  /// Where to open, as a fraction of the chapter. 1 opens on the last page.
  final double startFraction;

  final bool spread;
  final bool animate;

  /// The widest a page's text column gets.
  final double columnWidth;

  /// The paper colour, behind a page while it turns.
  final Color pageColor;

  /// Space kept clear above and below the pages, for the reader's bars.
  final double topInset;
  final double bottomInset;

  /// Called when the page or the page count changes. [turned] is true only when
  /// the reader turned the page, as opposed to the chapter being laid out again.
  final void Function(PagePosition position, {required bool turned}) onPage;

  /// Called to turn past the last page or back from the first.
  final VoidCallback onPastEnd;
  final VoidCallback onBeforeStart;

  /// Arriving from another chapter: the pages being left, as an image, and the
  /// direction of the turn (1 forward, -1 back). The new chapter's pages turn
  /// in once its first page is known.
  final ui.Image? arrivingFrom;
  final int arrivalDirection;

  /// Called once the arrival turn is over, so the image can be let go.
  final VoidCallback? onArrived;

  const PagedChapterView({
    super.key,
    required this.content,
    required this.startFraction,
    required this.spread,
    required this.animate,
    required this.columnWidth,
    required this.pageColor,
    required this.topInset,
    required this.bottomInset,
    required this.onPage,
    required this.onPastEnd,
    required this.onBeforeStart,
    this.arrivingFrom,
    this.arrivalDirection = 0,
    this.onArrived,
  });

  @override
  State<PagedChapterView> createState() => PagedChapterViewState();
}

class PagedChapterViewState extends State<PagedChapterView>
    with SingleTickerProviderStateMixin {
  static const _gap = 56.0;
  static const _sideMargin = 24.0;
  static const _turnDuration = Duration(milliseconds: 520);

  PageBreaks? _breaks;
  RenderBox? _laidOut;
  double _pageHeight = 0;

  /// The page shown, or in a spread the left-hand page (-1 when a chapter's
  /// first page stands alone on the right).
  int _page = 0;

  /// Where the reader is, kept as a fraction so a reflow (new size, new font)
  /// lands on the page holding the same text.
  late double _anchor = widget.startFraction;

  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: _turnDuration,
    value: 1,
  );
  int _turnDirection = 1;

  /// A turn in progress: the pages being left and the pages arriving, as
  /// images. The leaf that turns is cut from them.
  ui.Image? _from;
  bool _ownsFrom = false;
  ui.Image? _to;
  final _pagesKey = GlobalKey();
  bool _arrived = false;

  @override
  void initState() {
    super.initState();
    if (widget.arrivingFrom != null && widget.animate) {
      _from = widget.arrivingFrom;
      _turnDirection = widget.arrivalDirection < 0 ? -1 : 1;
      _turn.value = 0;
    }
  }

  int get _step => widget.spread ? 2 : 1;
  int get _firstPage => widget.spread ? -1 : 0;

  int get page => _page;
  int get pageCount => _breaks?.count ?? 0;

  @override
  void dispose() {
    _turn.dispose();
    _releaseImages();
    if (!_arrived) widget.onArrived?.call();
    super.dispose();
  }

  void _releaseImages() {
    if (_ownsFrom) _from?.dispose();
    _to?.dispose();
    _from = null;
    _to = null;
    _ownsFrom = false;
  }

  /// The pages on screen as an image. Null when nothing is painted yet.
  ui.Image? snapshot() {
    final boundary = _pagesKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary || !boundary.hasSize) return null;
    try {
      return boundary.toImageSync(
          pixelRatio: MediaQuery.devicePixelRatioOf(context));
    } catch (_) {
      return null; // Not painted yet: change pages without the turn.
    }
  }

  /// Turns from [from] (disposed here if [owned]) to the pages now built. The
  /// arriving pages are captured once they're painted, then the leaf turns.
  void _startTurn(ui.Image? from, int direction, {required bool owned}) {
    _turn.stop();
    if (!identical(from, _from)) {
      if (_ownsFrom) _from?.dispose();
    }
    _to?.dispose();
    _to = null;
    _from = from;
    _ownsFrom = owned;
    _turnDirection = direction;
    if (from == null) {
      _finishTurn();
      return;
    }
    _turn.value = 0;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_from, from)) return;
      final to = snapshot();
      if (to == null) {
        _finishTurn();
        return;
      }
      setState(() => _to = to);
      _turn.forward(from: 0).whenComplete(() {
        if (mounted && identical(_to, to)) _finishTurn();
      });
    });
  }

  void _finishTurn() {
    if (!mounted) return;
    setState(() {
      _releaseImages();
      _turn.value = 1;
    });
    if (!_arrived) {
      _arrived = true;
      widget.onArrived?.call();
    }
  }

  /// Turns to the next page, or past the chapter's end.
  void next() {
    final breaks = _breaks;
    if (breaks == null) return;
    if (_page + _step < breaks.count) {
      _turnTo(_page + _step, 1);
    } else {
      widget.onPastEnd();
    }
  }

  /// Turns back a page, or back past the chapter's start.
  void previous() {
    if (_breaks == null) return;
    if (_page > _firstPage) {
      _turnTo(math.max(_firstPage, _page - _step), -1);
    } else {
      widget.onBeforeStart();
    }
  }

  void _turnTo(int page, int direction) {
    final breaks = _breaks!;
    // Captured before the pages change, so it's what the reader is leaving.
    final leaving = widget.animate ? snapshot() : null;
    setState(() {
      _page = page;
      _anchor = breaks.fractionOf(page);
    });
    if (widget.animate) _startTurn(leaving, direction, owned: true);
    widget.onPage(_position, turned: true);
  }

  PagePosition get _position => (
        page: _page,
        count: _breaks?.count ?? 0,
        fraction: _breaks?.fractionOf(_page) ?? _anchor,
      );

  /// The spread holding [page] starts on the odd page before it, so pages keep
  /// their sides: the first page right, then 1–2, 3–4 by index.
  int _align(int page) => widget.spread ? (page.isOdd ? page : page - 1) : page;

  void _onLaidOut(RenderBox box) {
    _laidOut = box;
    _measure();
  }

  void _measure() {
    final box = _laidOut;
    if (!mounted || box == null || !box.attached || !box.hasSize) return;
    if (_pageHeight <= 0) return;
    final breaks = PageBreaks.compute(
      collectPageUnits(box),
      box.size.height,
      _pageHeight,
    );
    final first = _breaks == null;
    setState(() {
      _breaks = breaks;
      _page = _align(breaks.pageAt(_anchor));
    });
    widget.onPage(_position, turned: false);
    // Arriving from another chapter: turn in now that the right page is known.
    if (first && _from != null && _to == null && !_turn.isAnimating) {
      _startTurn(_from, _turnDirection, owned: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final pageHeight = math.max(
          0.0, constraints.maxHeight - widget.topInset - widget.bottomInset);
      if (pageHeight != _pageHeight) {
        _pageHeight = pageHeight;
        SchedulerBinding.instance.addPostFrameCallback((_) => _measure());
      }
      final fullWidth = constraints.maxWidth;
      final available = fullWidth - 2 * _sideMargin;
      final width = widget.spread
          ? math.min(widget.columnWidth, (available - _gap) / 2)
          : math.min(widget.columnWidth, available);

      // The right-hand page measures the chapter in a spread: on the opening
      // spread the left one is blank.
      final pages = <Widget>[
        _slot(_page, width, pageHeight, measure: !widget.spread),
        if (widget.spread) ...[
          const SizedBox(width: _gap),
          _slot(_page + 1, width, pageHeight, measure: true),
        ],
      ];

      final size = Size(fullWidth, pageHeight);
      return Padding(
        padding:
            EdgeInsets.only(top: widget.topInset, bottom: widget.bottomInset),
        child: ClipRect(
          child: AnimatedBuilder(
            animation: _turn,
            builder: (context, child) => Stack(
              children: [
                Opacity(
                  // Hidden until the first page breaks are known, so the
                  // chapter doesn't flash on its first page before moving to
                  // the saved one.
                  opacity: _breaks == null ? 0 : 1,
                  child: child,
                ),
                ..._turnLayers(size, width),
              ],
            ),
            child: RepaintBoundary(
              key: _pagesKey,
              child: SizedBox(
                width: fullWidth,
                height: pageHeight,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: pages,
                ),
              ),
            ),
          ),
        ),
      );
    });
  }

  /// What's drawn over the live pages during a turn.
  ///
  /// Forward in a spread, the right-hand page lifts about the spine and folds
  /// over: for the first half of the turn it's the old right page, seen edge-on
  /// at the middle; for the second half it's the new left page, landing on the
  /// old left page, which stays down until it's covered. The new right page lies
  /// beneath from the start. Back is the mirror. A single page lifts from its
  /// left edge going forward, and the previous page drops back onto it going
  /// back.
  List<Widget> _turnLayers(Size size, double pageWidth) {
    final from = _from;
    if (from == null) return const [];
    final to = _to;
    final whole = Offset.zero & size;
    if (to == null) {
      // Waiting for the arriving pages to paint: keep the old ones up.
      return [
        _Part(image: from, area: whole, rect: whole, paper: widget.pageColor)
      ];
    }

    final t = Curves.easeInOut.transform(_turn.value);
    final forward = _turnDirection > 0;
    final paper = widget.pageColor;

    if (!widget.spread) {
      final left = (size.width - pageWidth) / 2;
      final page = Rect.fromLTWH(left - 8, 0, pageWidth + 16, size.height);
      return forward
          ? [
              // The old page lifts away; the new one lies beneath.
              _leaf(from, page, size, math.pi / 2 * t, pivotLeft: true),
            ]
          : [
              // The old page stays down while the previous one drops onto it.
              _Part(image: from, area: whole, rect: page, paper: paper),
              _leaf(to, page, size, math.pi / 2 * (1 - t), pivotLeft: true),
            ];
    }

    final spine = size.width / 2;
    final leftHalf = Rect.fromLTRB(0, 0, spine, size.height);
    final rightHalf = Rect.fromLTRB(spine, 0, size.width, size.height);
    final firstHalf = t < 0.5;
    if (forward) {
      return [
        _Part(image: from, area: whole, rect: leftHalf, paper: paper),
        firstHalf
            ? _leaf(from, rightHalf, size, math.pi * t, pivotLeft: true)
            : _leaf(to, leftHalf, size, -math.pi * (1 - t), pivotLeft: false),
      ];
    }
    return [
      _Part(image: from, area: whole, rect: rightHalf, paper: paper),
      firstHalf
          ? _leaf(from, leftHalf, size, -math.pi * t, pivotLeft: false)
          : _leaf(to, rightHalf, size, math.pi * (1 - t), pivotLeft: true),
    ];
  }

  /// [rect] of [image], turned [angle] about its left or right edge, with the
  /// near edge coming towards the reader as paper does.
  Widget _leaf(ui.Image image, Rect rect, Size size, double angle,
      {required bool pivotLeft}) {
    // Darker as it stands up, lit again as it lies flat.
    final shade = 0.3 * math.sin(angle.abs().clamp(0.0, math.pi));
    return Positioned.fromRect(
      rect: rect,
      child: Transform(
        alignment: pivotLeft ? Alignment.centerLeft : Alignment.centerRight,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0012)
          ..rotateY(angle),
        child: _Part(
          image: image,
          area: Offset.zero & size,
          rect: rect,
          paper: widget.pageColor,
          shade: shade,
          positioned: false,
        ),
      ),
    );
  }

  /// One page: a window onto the laid-out chapter, from the page's start to its
  /// end, so the next page's first line never shows cut off at the bottom. A
  /// page outside the chapter, such as the blank left page opening a spread, is
  /// empty, but still lays the chapter out if it's the one measuring it.
  Widget _slot(int page, double width, double pageHeight,
      {required bool measure}) {
    final breaks = _breaks;
    final outside = page < 0 || (breaks != null && page >= breaks.count);
    if (outside && !measure) return SizedBox(width: width, height: pageHeight);

    final start = breaks == null || outside ? 0.0 : breaks.starts[page];
    final visible = outside
        ? 0.0
        : breaks == null
            ? pageHeight
            : math.min(pageHeight, breaks.ends[page] - start);

    Widget content = widget.content;
    if (measure) {
      content = _LayoutReporter(onLayout: _onLaidOut, child: content);
    }

    return SizedBox(
      width: width,
      height: pageHeight,
      child: Align(
        alignment: Alignment.topCenter,
        child: ClipRect(
          child: SizedBox(
            width: width,
            height: math.max(0.0, visible),
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: width,
              maxWidth: width,
              minHeight: 0,
              maxHeight: double.infinity,
              child: Transform.translate(
                offset: Offset(0, -start),
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Part of a page image: [rect] of an image of [area], on paper, optionally
/// shaded. Positioned at [rect] unless [positioned] is false, when it fills its
/// parent.
class _Part extends StatelessWidget {
  final ui.Image image;
  final Rect area;
  final Rect rect;
  final Color paper;
  final double shade;
  final bool positioned;

  const _Part({
    required this.image,
    required this.area,
    required this.rect,
    required this.paper,
    this.shade = 0,
    this.positioned = true,
  });

  @override
  Widget build(BuildContext context) {
    final painted = IgnorePointer(
      child: CustomPaint(
        size: rect.size,
        painter: _PartPainter(image, area, rect, paper, shade),
      ),
    );
    return positioned
        ? Positioned.fromRect(rect: rect, child: painted)
        : painted;
  }
}

class _PartPainter extends CustomPainter {
  final ui.Image image;
  final Rect area;
  final Rect rect;
  final Color paper;
  final double shade;

  _PartPainter(this.image, this.area, this.rect, this.paper, this.shade);

  @override
  void paint(Canvas canvas, Size size) {
    final dst = Offset.zero & size;
    canvas.drawRect(dst, Paint()..color = paper.withValues(alpha: 1));
    // The image is of the whole area, at the screen's pixel ratio.
    final scaleX = image.width / area.width;
    final scaleY = image.height / area.height;
    final src = Rect.fromLTRB(
      rect.left * scaleX,
      rect.top * scaleY,
      rect.right * scaleX,
      rect.bottom * scaleY,
    ).intersect(
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()));
    if (!src.isEmpty) {
      canvas.drawImageRect(
          image, src, dst, Paint()..filterQuality = FilterQuality.medium);
    }
    if (shade > 0) {
      canvas.drawRect(dst,
          Paint()..color = const Color(0xFF000000).withValues(alpha: shade));
    }
  }

  @override
  bool shouldRepaint(_PartPainter old) =>
      !identical(old.image, image) ||
      old.rect != rect ||
      old.shade != shade ||
      old.paper != paper;
}

/// Reports its child's render box after each layout that changes its size, such
/// as the chapter finishing building or an image arriving.
class _LayoutReporter extends SingleChildRenderObjectWidget {
  final void Function(RenderBox box) onLayout;

  const _LayoutReporter({required this.onLayout, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLayoutReporter(onLayout);

  @override
  void updateRenderObject(
          BuildContext context, _RenderLayoutReporter renderObject) =>
      renderObject.onLayout = onLayout;
}

class _RenderLayoutReporter extends RenderProxyBox {
  void Function(RenderBox box) onLayout;
  Size? _reported;

  _RenderLayoutReporter(this.onLayout);

  @override
  void performLayout() {
    super.performLayout();
    if (size == _reported) return;
    _reported = size;
    // Measuring walks the laid-out tree, which can only happen once this
    // frame's layout is done.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (attached) onLayout(this);
    });
  }
}
