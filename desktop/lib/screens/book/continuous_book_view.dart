import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/epub/epub_parser.dart';
import '../../core/epub/reader_book.dart';

/// The whole book as one scroll: each chapter follows the last. Chapters are
/// fetched as they come near, in both directions, and the one under the reading
/// line is the current chapter.
class ContinuousBookView extends StatefulWidget {
  final ReaderBook book;
  final int startChapter;

  /// How far into [startChapter] to open, as a fraction of it.
  final double startFraction;

  final Widget Function(EpubChapter chapter) buildChapter;

  /// Called as the reader scrolls. [settled] is true once a scroll has ended,
  /// which is when the position is worth saving.
  final void Function(int chapter, double fraction, {required bool settled})
      onPosition;

  /// Space under the reader's bars. The reading line sits just below the top one.
  final double topInset;
  final double bottomInset;

  const ContinuousBookView({
    super.key,
    required this.book,
    required this.startChapter,
    required this.startFraction,
    required this.buildChapter,
    required this.onPosition,
    required this.topInset,
    required this.bottomInset,
  });

  @override
  State<ContinuousBookView> createState() => ContinuousBookViewState();
}

class ContinuousBookViewState extends State<ContinuousBookView> {
  /// How long the opening position keeps being re-applied while chapters build.
  static const _restoreWindow = Duration(seconds: 2);

  /// Chapters further than this from the current one are let go.
  static const _keepAround = 3;

  final _centerKey = UniqueKey();
  final _scroll = ScrollController();
  final Map<int, Future<EpubChapter>> _chapters = {};
  final Map<int, GlobalKey> _keys = {};

  late int _current = widget.startChapter;
  double? _restoring;
  final DateTime _restoreUntil = DateTime.now().add(_restoreWindow);

  @override
  void initState() {
    super.initState();
    _restoring = widget.startFraction;
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Hands over from a pending restore: the reader has taken over.
  void cancelRestore() => _restoring = null;

  Future<EpubChapter> _load(int index) =>
      _chapters[index] ??= widget.book.loadChapter(index);

  double get _readingLine => widget.topInset + 1;

  RenderBox? _boxOf(int index) {
    final box = _keys[index]?.currentContext?.findRenderObject();
    return box is RenderBox && box.attached && box.hasSize ? box : null;
  }

  /// Top of chapter [index] in this view, if it's built.
  double? _topOf(int index) {
    final box = _boxOf(index);
    final root = context.findRenderObject();
    if (box == null || root is! RenderBox) return null;
    return box.localToGlobal(Offset.zero, ancestor: root).dy;
  }

  void _applyRestore() {
    final fraction = _restoring;
    if (fraction == null || !mounted || !_scroll.hasClients) return;
    if (DateTime.now().isAfter(_restoreUntil)) {
      _restoring = null;
      return;
    }
    final box = _boxOf(widget.startChapter);
    final top = _topOf(widget.startChapter);
    if (box == null || top == null) return;
    final delta = top + fraction * box.size.height - _readingLine;
    if (delta.abs() > 1) _scroll.jumpTo(_scroll.offset + delta);
  }

  /// The chapter under the reading line, and how far through it that line is.
  ({int chapter, double fraction})? _locate() {
    for (final index in _keys.keys) {
      final box = _boxOf(index);
      final top = _topOf(index);
      if (box == null || top == null) continue;
      final height = box.size.height;
      if (top <= _readingLine && top + height > _readingLine) {
        return (
          chapter: index,
          fraction: ((_readingLine - top) / height).clamp(0.0, 1.0),
        );
      }
    }
    return null;
  }

  bool _onNotification(Notification notification) {
    if (notification is ScrollMetricsNotification) {
      SchedulerBinding.instance.addPostFrameCallback((_) => _applyRestore());
    }
    if (_restoring != null) return false;
    if (notification is ScrollUpdateNotification ||
        notification is ScrollEndNotification) {
      final here = _locate();
      if (here == null) return false;
      if (here.chapter != _current) {
        _current = here.chapter;
        _chapters.removeWhere((i, _) => (i - _current).abs() > _keepAround);
      }
      widget.onPosition(here.chapter, here.fraction,
          settled: notification is ScrollEndNotification);
    }
    return false;
  }

  Widget _chapter(int index) {
    final key = _keys.putIfAbsent(index, GlobalKey.new);
    return KeyedSubtree(
      key: key,
      child: FutureBuilder<EpubChapter>(
        future: _load(index),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 64),
              child: widget.buildChapter(snapshot.data!),
            );
          }
          if (snapshot.hasError) {
            return SizedBox(
              height: 240,
              child: Center(
                child: TextButton(
                  onPressed: () => setState(() => _chapters.remove(index)),
                  child:
                      const Text("This chapter couldn't be loaded. Try again"),
                ),
              ),
            );
          }
          // Roughly a screen tall, so the view doesn't jump much as it fills.
          return const SizedBox(
            height: 600,
            child: Center(child: CircularProgressIndicator()),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final start = widget.startChapter;
    final count = widget.book.chapterCount;
    return Listener(
      onPointerDown: (_) => cancelRestore(),
      onPointerSignal: (_) => cancelRestore(),
      child: NotificationListener<Notification>(
        onNotification: _onNotification,
        child: CustomScrollView(
          controller: _scroll,
          center: _centerKey,
          // Starts the opening chapter at the reading line, under the top bar.
          anchor: 0,
          slivers: [
            // Earlier chapters grow upwards from the opening one.
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => i == start
                    ? SizedBox(height: widget.topInset)
                    : _chapter(start - 1 - i),
                childCount: start + 1,
              ),
            ),
            SliverList(
              key: _centerKey,
              delegate: SliverChildBuilderDelegate(
                (context, i) => i == count - start
                    ? SizedBox(height: widget.bottomInset)
                    : _chapter(start + i),
                childCount: count - start + 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
