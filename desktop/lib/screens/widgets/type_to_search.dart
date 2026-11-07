import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Turns typing into a search on a browsing screen.
///
/// While nothing else on the screen takes the keyboard, a printable character
/// goes to [onType] instead of being lost; the screen shows its search with
/// that text. Escape goes to [onEscape] while the search is [active], so it
/// closes the search rather than leaving the screen.
///
/// Keys it doesn't use pass through untouched: anything with Ctrl, Alt or Meta
/// held, keys that type nothing, and every key while a text field has focus,
/// the search field included, which handles its own typing.
class TypeToSearch extends StatefulWidget {
  /// Whether typing opens the search. Escape still closes an open one.
  final bool enabled;

  /// Whether the screen's search is showing.
  final bool active;

  /// Receives the typed text. The screen opens its search with it, or adds it
  /// to the search already open.
  final ValueChanged<String> onType;

  /// Called on Escape while [active].
  final VoidCallback onEscape;

  final Widget child;

  const TypeToSearch({
    super.key,
    required this.enabled,
    required this.active,
    required this.onType,
    required this.onEscape,
    required this.child,
  });

  /// The text [event] types, or null when it types nothing.
  static String? typedText(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return null;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return null;
    }
    final text = event.character;
    if (text == null || text.isEmpty) return null;
    // Control characters: Tab, Enter, Backspace, Delete, Escape and so on.
    if (text.runes.any((r) => r < 0x20 || r == 0x7f)) return null;
    return text;
  }

  @override
  State<TypeToSearch> createState() => _TypeToSearchState();
}

class _TypeToSearchState extends State<TypeToSearch> {
  final _node = FocusNode(debugLabel: 'TypeToSearch');

  @override
  void didUpdateWidget(TypeToSearch old) {
    super.didUpdateWidget(old);
    // Closing the search removes its field, and focus would go with it, out of
    // reach of the next key. Take it back so typing still works.
    if (old.active && !widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_node.hasFocus) _node.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  static bool _inTextField() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    return context.widget is EditableText ||
        context.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (widget.active &&
        event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onEscape();
      return KeyEventResult.handled;
    }
    if (!widget.enabled || _inTextField()) return KeyEventResult.ignored;
    final text = TypeToSearch.typedText(event);
    if (text == null) return KeyEventResult.ignored;
    // A space alone starts nothing; it's left to whatever button has focus.
    if (!widget.active && text.trim().isEmpty) return KeyEventResult.ignored;
    widget.onType(text);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _node,
      autofocus: true,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: widget.child,
    );
  }
}
