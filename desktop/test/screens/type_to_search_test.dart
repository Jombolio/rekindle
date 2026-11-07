import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rekindle/core/models/media.dart';
import 'package:rekindle/screens/chapter_index_screen.dart';
import 'package:rekindle/screens/widgets/type_to_search.dart';

/// A browsing screen in miniature, built the way the library screens use
/// [TypeToSearch]: a list that filters, and a search bar that appears holding
/// what was typed.
class _Browser extends StatefulWidget {
  final bool enabled;
  final List<String> names;
  const _Browser({this.enabled = true, required this.names});

  @override
  State<_Browser> createState() => _BrowserState();
}

class _BrowserState extends State<_Browser> {
  bool active = false;
  final ctrl = TextEditingController();
  final focus = FocusNode();
  int escapesPassedOn = 0;

  void onType(String text) {
    ctrl.value = TextEditingValue(
      text: ctrl.text + text,
      selection:
          TextSelection.collapsed(offset: ctrl.text.length + text.length),
    );
    setState(() => active = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => focus.requestFocus());
  }

  void close() {
    ctrl.clear();
    setState(() => active = false);
  }

  @override
  Widget build(BuildContext context) {
    final q = ctrl.text.toLowerCase();
    // Stands in for EscapeGoesBack, which sits above every screen.
    return Focus(
      onKeyEvent: (_, e) {
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
          escapesPassedOn++;
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: TypeToSearch(
        enabled: widget.enabled,
        active: active,
        onType: onType,
        onEscape: close,
        child: Scaffold(
          appBar: AppBar(
            title: active
                ? TextField(
                    key: const Key('search'),
                    controller: ctrl,
                    focusNode: focus,
                    onChanged: (v) => v.isEmpty ? close() : setState(() {}),
                  )
                : const Text('Library'),
          ),
          body: Column(
            children: [
              const TextField(key: Key('other')),
              for (final n in widget.names)
                if (n.toLowerCase().contains(q)) Text(n),
            ],
          ),
        ),
      ),
    );
  }
}

void main() {
  const names = ['Batman', 'Berserk', 'Naruto'];

  Future<_BrowserState> pump(WidgetTester tester, {bool enabled = true}) async {
    await tester.pumpWidget(
        MaterialApp(home: _Browser(enabled: enabled, names: names)));
    await tester.pump();
    return tester.state<_BrowserState>(find.byType(_Browser));
  }

  testWidgets('typing opens the search and filters the listing',
      (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('search')), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.pump();
    expect(find.byKey(const Key('search')), findsOneWidget);
    expect(find.text('Batman'), findsOneWidget);
    expect(find.text('Berserk'), findsOneWidget);
    expect(find.text('Naruto'), findsNothing);

    // Later keys land in the search field itself.
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.enterText(find.byKey(const Key('search')), 'bat');
    await tester.pump();
    expect(find.text('Batman'), findsOneWidget);
    expect(find.text('Berserk'), findsNothing);
  });

  testWidgets('Escape closes the search instead of leaving the screen',
      (tester) async {
    final state = await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.pump();
    await tester.pump();
    expect(find.text('Batman'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byKey(const Key('search')), findsNothing);
    expect(find.text('Batman'), findsOneWidget);
    expect(state.escapesPassedOn, 0);

    // With the search closed, Escape goes on as before (it goes back).
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(state.escapesPassedOn, 1);

    // And typing still opens the search after it was closed.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pump();
    expect(find.byKey(const Key('search')), findsOneWidget);
  });

  testWidgets('emptying the search brings the full listing back',
      (tester) async {
    await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.pump();
    await tester.pump();
    await tester.enterText(find.byKey(const Key('search')), '');
    await tester.pump();
    expect(find.byKey(const Key('search')), findsNothing);
    for (final n in names) {
      expect(find.text(n), findsOneWidget);
    }
  });

  testWidgets('typing in another text field does not search', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('other')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.pump();
    expect(find.byKey(const Key('search')), findsNothing);
  });

  testWidgets('shortcuts, spaces and non-typing keys pass through',
      (tester) async {
    await pump(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.byKey(const Key('search')), findsNothing);
  });

  testWidgets('the setting turns it off', (tester) async {
    await pump(tester, enabled: false);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.pump();
    expect(find.byKey(const Key('search')), findsNothing);
    expect(find.text('Naruto'), findsOneWidget);
  });

  group('matchesFolderSearch', () {
    Media item(String title, String path) => Media.fromJson({
          'id': title,
          'libraryId': 'lib',
          'title': title,
          'filePath': '/x',
          'format': 'cbz',
          'mediaType': 'archive',
          'relativePath': path,
        });

    test('matches title or file name, ignoring case', () {
      final m = item('Chapter 10', 'Batman/batman_c010.cbz');
      expect(matchesFolderSearch(m, 'chap'), isTrue);
      expect(matchesFolderSearch(m, 'C010'), isTrue);
      expect(matchesFolderSearch(m, '  '), isTrue);
      expect(matchesFolderSearch(m, 'naruto'), isFalse);
      // The folder it sits in isn't part of its name.
      expect(matchesFolderSearch(item('Chapter 1', 'Batman/c1.cbz'), 'batman'),
          isFalse);
    });
  });
}
