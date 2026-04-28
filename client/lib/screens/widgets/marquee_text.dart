import 'package:flutter/material.dart';

/// Single-line text that auto-scrolls horizontally when its content overflows.
///
/// When the text fits within the available width it is displayed as a plain
/// [Text] respecting [textAlign] (so titles stay centred in grid cells).
/// When the text overflows the available width it scrolls continuously from
/// start to end, pauses, snaps back, and repeats — the user cannot manually
/// scroll.
class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final TextAlign textAlign;

  const MarqueeText({
    super.key,
    required this.text,
    this.style,
    this.textAlign = TextAlign.start,
  });

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> {
  final _controller = ScrollController();

  /// Whether we have completed the post-layout overflow measurement.
  bool _measured = false;

  /// True once we know the text is wider than its container.
  bool _overflows = false;

  bool _scrolling = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _onLayout());
  }

  @override
  void didUpdateWidget(MarqueeText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      // Reset so the scrollable is shown again for re-measurement.
      if (_controller.hasClients) _controller.jumpTo(0);
      setState(() {
        _measured = false;
        _overflows = false;
        _scrolling = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _onLayout());
    }
  }

  void _onLayout() {
    if (!mounted || !_controller.hasClients) return;
    final max = _controller.position.maxScrollExtent;
    final overflows = max > 0;
    if (!_measured || overflows != _overflows) {
      setState(() {
        _measured = true;
        _overflows = overflows;
      });
    }
    if (overflows && !_scrolling) _startScrolling(max);
  }

  Future<void> _startScrolling(double max) async {
    _scrolling = true;
    try {
      while (mounted) {
        // Pause so the beginning of the title is readable before scrolling.
        await Future.delayed(const Duration(seconds: 2));
        if (!mounted) break;

        // Scroll to end at ~40 logical pixels per second.
        await _controller.animateTo(
          max,
          duration:
              Duration(milliseconds: (max / 40 * 1000).clamp(800, 8000).toInt()),
          curve: Curves.linear,
        );
        if (!mounted) break;

        // Brief pause at the end before snapping back.
        await Future.delayed(const Duration(milliseconds: 800));
        if (!mounted) break;

        _controller.jumpTo(0);
      }
    } catch (_) {
      // ScrollController disposed during animation — safe to ignore.
    }
    _scrolling = false;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // After measurement: text fits → render as a plain Text so textAlign works.
    if (_measured && !_overflows) {
      return Text(
        widget.text,
        style: widget.style,
        maxLines: 1,
        overflow: TextOverflow.clip,
        textAlign: widget.textAlign,
      );
    }

    // Before measurement (first frame) OR text overflows → use the scrollable.
    // The controller is attached here for both measurement and animation.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      controller: _controller,
      physics: const NeverScrollableScrollPhysics(),
      child: Text(
        widget.text,
        style: widget.style,
        maxLines: 1,
        softWrap: false,
      ),
    );
  }
}
