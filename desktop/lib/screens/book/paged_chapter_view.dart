import 'dart:math' as math;

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

  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: 1,
  );
  int _turnDirection = 1;

  int get _step => widget.spread ? 2 : 1;

  /// The page shown, or the left page of the spread.
  int get page => _page;
  int get pageCount => _breaks?.count ?? 0;

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
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
    setState(() {
      _page = page;
      _anchor = breaks.fractionOf(page);
    });
    _turnDirection = direction;
    if (widget.animate) _turn.forward(from: 0);
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
    setState(() {
      _breaks = breaks;
      _page = _align(breaks.pageAt(_anchor));
    });
    widget.onPage(_position, turned: false);
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

      return Padding(
        padding:
            EdgeInsets.only(top: widget.topInset, bottom: widget.bottomInset),
        child: AnimatedBuilder(
          animation: _turn,
          builder: (context, child) {
            final t = Curves.easeOut.transform(_turn.value);
            return Opacity(
              // Hidden until the first page breaks are known, so the chapter
              // doesn't flash on its first page before jumping to the saved one.
              opacity: _breaks == null ? 0 : 0.35 + 0.65 * t,
              child: Transform.translate(
                offset: Offset((1 - t) * 48 * _turnDirection, 0),
                child: child,
              ),
            );
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: pages,
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
