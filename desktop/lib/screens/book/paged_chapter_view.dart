import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../core/epub/page_breaks.dart';

/// Where a paged chapter is, for the reader to show and save.
typedef PagePosition = ({int page, int count, double fraction});

/// One chapter shown a page, or a two-page spread, at a time.
///
/// The chapter is laid out once at the column's width, and each page is a
/// window onto it, cut between lines (see [PageBreaks]). Turning a page only
/// moves the window, so it costs no rebuild.
class PagedChapterView extends StatefulWidget {
  /// The whole chapter. Shown once per visible page.
  final Widget content;

  /// Where to open, as a fraction of the chapter. 1 opens on the last page.
  final double startFraction;

  final bool spread;
  final bool animate;

  /// The widest a page's text column gets.
  final double columnWidth;

  /// Space kept clear above and below the pages, for the reader's bars.
  final double topInset;
  final double bottomInset;

  /// Called when the page or the page count changes. [turned] is true only when
  /// the reader turned the page, as opposed to the chapter being laid out again.
  final void Function(PagePosition position, {required bool turned}) onPage;

  /// Called to turn past the last page or back from the first.
  final VoidCallback onPastEnd;
  final VoidCallback onBeforeStart;

  /// Arriving from another chapter: the page being left, as an image, and the
  /// direction to slide (1 forward, -1 back). The new chapter slides in once
  /// its first page is known, pushing the old page out.
  final ui.Image? arrivingFrom;
  final int arrivalDirection;

  /// Called once the arrival slide is over, so the image can be let go.
  final VoidCallback? onArrived;

  const PagedChapterView({
    super.key,
    required this.content,
    required this.startFraction,
    required this.spread,
    required this.animate,
    required this.columnWidth,
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

  PageBreaks? _breaks;
  RenderBox? _laidOut;
  double _pageHeight = 0;
  int _page = 0;

  /// Where the reader is, kept as a fraction so a reflow (new size, new font)
  /// lands on the page holding the same text.
  late double _anchor = widget.startFraction;

  static const _turnDuration = Duration(milliseconds: 300);

  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: _turnDuration,
    value: 1,
  );
  int _turnDirection = 1;

  /// The pages being turned away from, as an image, while they slide out.
  ui.Image? _outgoing;
  bool _ownsOutgoing = false;
  final _pagesKey = GlobalKey();
  bool _arrived = false;

  @override
  void initState() {
    super.initState();
    if (widget.arrivingFrom != null && widget.animate) {
      _outgoing = widget.arrivingFrom;
      _turnDirection =
          widget.arrivalDirection == 0 ? 1 : widget.arrivalDirection;
      _turn.value = 0;
    }
  }

  int get _step => widget.spread ? 2 : 1;

  /// The page shown, or the left page of the spread.
  int get page => _page;
  int get pageCount => _breaks?.count ?? 0;

  @override
  void dispose() {
    _turn.dispose();
    _releaseOutgoing();
    if (!_arrived) widget.onArrived?.call();
    super.dispose();
  }

  void _releaseOutgoing() {
    if (_ownsOutgoing) _outgoing?.dispose();
    _outgoing = null;
    _ownsOutgoing = false;
  }

  /// The pages on screen as an image, to slide out as the next ones come in.
  /// Null when there's nothing painted to capture yet.
  ui.Image? snapshot() {
    final boundary = _pagesKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary || !boundary.hasSize) return null;
    try {
      return boundary.toImageSync(
          pixelRatio: MediaQuery.devicePixelRatioOf(context));
    } catch (_) {
      return null; // Not painted yet: turn without the slide.
    }
  }

  /// Slides from [outgoing] (disposed here if [owned]) to what's built now.
  void _slide(ui.Image? outgoing, int direction, {required bool owned}) {
    if (!identical(outgoing, _outgoing)) _releaseOutgoing();
    _outgoing = outgoing;
    _ownsOutgoing = owned;
    _turnDirection = direction;
    _turn.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      setState(_releaseOutgoing);
      if (!_arrived) {
        _arrived = true;
        widget.onArrived?.call();
      }
    });
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
    if (_page > 0) {
      _turnTo(math.max(0, _page - _step), -1);
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
    if (widget.animate) _slide(leaving, direction, owned: true);
    widget.onPage(_position, turned: true);
  }

  PagePosition get _position => (
        page: _page,
        count: _breaks?.count ?? 0,
        fraction: _breaks?.fractionOf(_page) ?? _anchor,
      );

  /// A spread always starts on an even page, so pages keep their sides.
  int _align(int page) => widget.spread ? page - page % 2 : page;

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
    // Arriving from another chapter: slide in now that the right page is known.
    if (first && _outgoing != null && !_turn.isAnimating && _turn.value == 0) {
      _slide(_outgoing, _turnDirection, owned: false);
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
      final available = constraints.maxWidth - 2 * _sideMargin;
      final width = widget.spread
          ? math.min(widget.columnWidth, (available - _gap) / 2)
          : math.min(widget.columnWidth, available);

      final pages = <Widget>[
        _slot(_page, width, pageHeight, measure: true),
        if (widget.spread) ...[
          const SizedBox(width: _gap),
          _slot(_page + 1, width, pageHeight, measure: false),
        ],
      ];

      final fullWidth = constraints.maxWidth;
      return Padding(
        padding:
            EdgeInsets.only(top: widget.topInset, bottom: widget.bottomInset),
        child: ClipRect(
          child: AnimatedBuilder(
            animation: _turn,
            builder: (context, child) {
              final t = Curves.easeInOutCubic.transform(_turn.value);
              final outgoing = _outgoing;
              // The new pages come in from the side being turned towards while
              // the old ones leave by the other, edge to edge, like a slide.
              return Stack(
                children: [
                  Opacity(
                    // Hidden until the first page breaks are known, so the
                    // chapter doesn't flash on its first page before moving to
                    // the saved one.
                    opacity: _breaks == null ? 0 : 1,
                    child: Transform.translate(
                      offset: Offset((1 - t) * fullWidth * _turnDirection, 0),
                      child: child,
                    ),
                  ),
                  if (outgoing != null)
                    Transform.translate(
                      offset: Offset(-t * fullWidth * _turnDirection, 0),
                      child: RawImage(
                        image: outgoing,
                        width: fullWidth,
                        height: pageHeight,
                        fit: BoxFit.fill,
                      ),
                    ),
                ],
              );
            },
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

  /// One page: a window onto the laid-out chapter, from the page's start to its
  /// end, so the next page's first line never shows cut off at the bottom.
  Widget _slot(int page, double width, double pageHeight,
      {required bool measure}) {
    final breaks = _breaks;
    if (breaks != null && page >= breaks.count) {
      return SizedBox(width: width, height: pageHeight);
    }
    final start = breaks == null ? 0.0 : breaks.starts[page];
    final visible = breaks == null
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
