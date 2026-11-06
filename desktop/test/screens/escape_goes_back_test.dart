import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rekindle/screens/widgets/escape_goes_back.dart';

void main() {
  late GoRouter router;

  Widget page(String name) => Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text(name)),
          endDrawer: const Drawer(child: Text('drawer')),
          body: Column(
            children: [
              TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const AlertDialog(content: Text('dialog')),
                ),
                child: const Text('open dialog'),
              ),
              Builder(
                builder: (context) => TextButton(
                  onPressed: () => Scaffold.of(context).openEndDrawer(),
                  child: const Text('open drawer'),
                ),
              ),
            ],
          ),
        ),
      );

  Future<void> pumpApp(WidgetTester tester) async {
    router = GoRouter(
      initialLocation: '/libraries',
      routes: [
        GoRoute(path: '/libraries', builder: (_, __) => page('Libraries')),
        GoRoute(path: '/series/:id', builder: (_, __) => page('Series')),
        GoRoute(path: '/settings', builder: (_, __) => page('Settings')),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(
      routerConfig: router,
      builder: (context, child) =>
          EscapeGoesBack(router: router, child: child!),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> escape(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  }

  String here() =>
      router.routerDelegate.currentConfiguration.last.matchedLocation;

  testWidgets('goes back a screen at a time, ending at the libraries',
      (tester) async {
    await pumpApp(tester);
    router.push('/series/1');
    await tester.pumpAndSettle();
    router.push('/series/2');
    await tester.pumpAndSettle();

    await escape(tester);
    expect(here(), '/series/1');
    await escape(tester);
    expect(here(), '/libraries');
    // Nothing further back: it stays.
    await escape(tester);
    expect(here(), '/libraries');
    expect(find.text('Libraries'), findsOneWidget);
  });

  testWidgets(
      'a screen switched to, with nothing to pop, goes to the libraries',
      (tester) async {
    await pumpApp(tester);
    router.go('/settings');
    await tester.pumpAndSettle();
    await escape(tester);
    expect(here(), '/libraries');
  });

  testWidgets('closes a dialog first, without leaving the screen',
      (tester) async {
    await pumpApp(tester);
    router.push('/series/1');
    await tester.pumpAndSettle();
    await tester.tap(find.text('open dialog'));
    await tester.pumpAndSettle();
    expect(find.text('dialog'), findsOneWidget);

    await escape(tester);
    expect(find.text('dialog'), findsNothing);
    expect(here(), '/series/1');
  });

  testWidgets('closes a drawer first, without leaving the screen',
      (tester) async {
    await pumpApp(tester);
    router.push('/series/1');
    await tester.pumpAndSettle();
    await tester.tap(find.text('open drawer'));
    await tester.pumpAndSettle();
    expect(find.text('drawer'), findsOneWidget);

    await escape(tester);
    expect(find.text('drawer'), findsNothing);
    expect(here(), '/series/1');
  });

  testWidgets('works while typing in a text field', (tester) async {
    router = GoRouter(
      initialLocation: '/libraries',
      routes: [
        GoRoute(path: '/libraries', builder: (_, __) => page('Libraries')),
        GoRoute(
          path: '/search',
          builder: (_, __) => const Scaffold(body: TextField(autofocus: true)),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(
      routerConfig: router,
      builder: (context, child) =>
          EscapeGoesBack(router: router, child: child!),
    ));
    await tester.pumpAndSettle();
    router.push('/search');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'dune');

    await escape(tester);
    expect(here(), '/libraries');
  });
}
