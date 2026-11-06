import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Makes Escape go back, anywhere in the app: one press leaves the current
/// screen, and pressing it repeatedly ends at the libraries, the main screen.
///
/// It only acts on an Escape nothing else used. Dialogs, menus, drawers and the
/// reader's definition pop-up handle Escape themselves to close, so a press
/// closes those first rather than leaving the screen beneath them.
class EscapeGoesBack extends StatelessWidget {
  /// Where Escape ends up when there's nothing to go back to.
  static const home = '/libraries';

  final GoRouter router;
  final Widget child;

  const EscapeGoesBack({super.key, required this.router, required this.child});

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    final navigator = router.routerDelegate.navigatorKey.currentState;
    if (navigator != null && navigator.canPop()) {
      navigator.maybePop();
      return KeyEventResult.handled;
    }
    // Screens reached by switching rather than opening have nothing to pop to.
    final matches = router.routerDelegate.currentConfiguration;
    if (matches.isEmpty) return KeyEventResult.ignored;
    final here = matches.last.matchedLocation;
    if (here != home && !here.startsWith('/source/add')) {
      router.go(home);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    // Autofocus keeps this in the path of key events even on a screen where
    // nothing has focus. Screens take focus inside it, so their keys still go
    // to them first and only an unused Escape reaches this.
    return Focus(
      autofocus: true,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: child,
    );
  }
}
