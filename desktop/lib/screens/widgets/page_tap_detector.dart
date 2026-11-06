import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Reports a plain tap on a page whose text can be selected. An ordinary tap gesture
/// can't work there: selection claims every pointer it sees. This watches the pointer
/// without competing for it, and waits briefly so the first half of a double-click,
/// which selects a word, doesn't count as a tap.
class PageTapDetector extends StatefulWidget {
  static const secondTapWindow = Duration(milliseconds: 260);
  static const _maxHold = Duration(milliseconds: 500);
  static const _maxTravel = 8.0;

  /// Where the tap landed, in global coordinates.
  final void Function(Offset position) onTap;
  final Widget child;

  const PageTapDetector({super.key, required this.onTap, required this.child});

  @override
  State<PageTapDetector> createState() => _PageTapDetectorState();
}

class _PageTapDetectorState extends State<PageTapDetector> {
  Offset? _downAt;
  Duration? _downTime;
  Timer? _pending;

  @override
  void dispose() {
    _pending?.cancel();
    super.dispose();
  }

  void _onDown(PointerDownEvent event) {
    // A second press this soon is a double-click, and the first wasn't a tap.
    _pending?.cancel();
    final wasPending = _pending != null;
    _pending = null;
    final primary = event.kind != PointerDeviceKind.mouse ||
        event.buttons == kPrimaryMouseButton;
    _downAt = primary && !wasPending ? event.position : null;
    _downTime = event.timeStamp;
  }

  void _onUp(PointerUpEvent event) {
    final downAt = _downAt;
    _downAt = null;
    if (downAt == null) return;
    if ((event.position - downAt).distance > PageTapDetector._maxTravel) return;
    if (event.timeStamp - _downTime! > PageTapDetector._maxHold) return;
    final at = event.position;
    _pending = Timer(PageTapDetector.secondTapWindow, () {
      _pending = null;
      if (mounted) widget.onTap(at);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onDown,
      onPointerUp: _onUp,
      onPointerCancel: (_) => _downAt = null,
      child: widget.child,
    );
  }
}
