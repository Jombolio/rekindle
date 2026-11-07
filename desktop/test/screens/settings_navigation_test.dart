import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rekindle/core/storage/prefs.dart';
import 'package:rekindle/screens/settings_screen.dart';
import 'package:rekindle/screens/widgets/comic_page_turn.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    PackageInfo.setMockInitialValues(
        appName: 'Rekindle',
        packageName: 'rekindle',
        version: '1.5.1',
        buildNumber: '1',
        buildSignature: '');
  });

  testWidgets('settings categories open independently and preserve preferences',
      (tester) async {
    await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: SettingsScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Show file extensions'), findsNothing);
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    expect(find.text('Show file extensions'), findsOneWidget);
    expect(find.text('Confirm chapter change'), findsNothing);
    await tester
        .tap(find.widgetWithText(SwitchListTile, 'Show file extensions'));
    await tester.pumpAndSettle();
    expect(Prefs.instance.showFileExtensions, isTrue);
    expect(Prefs.instance.typeToSearch, isTrue);
    await tester.tap(find.widgetWithText(SwitchListTile, 'Type to search'));
    await tester.pumpAndSettle();
    expect(Prefs.instance.typeToSearch, isFalse);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reader'));
    await tester.pumpAndSettle();
    expect(find.text('Comic and manga page turns'), findsOneWidget);
    expect(find.text('Show file extensions'), findsNothing);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(Prefs.instance.comicPageTurns, isFalse);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  for (final reverse in [false, true]) {
    testWidgets('comic turn settles without a blank page, RTL=$reverse',
        (tester) async {
      final controller = PageController();
      await tester.pumpWidget(MaterialApp(
          home: SizedBox.expand(
              child: PageView.builder(
        controller: controller,
        reverse: reverse,
        itemCount: 3,
        itemBuilder: (_, index) => ComicPageTurn(
          controller: controller,
          index: index,
          reverse: reverse,
          child: Center(child: Text('Page $index')),
        ),
      ))));
      expect(find.text('Page 0'), findsOneWidget);
      final animation = controller.animateToPage(1,
          duration: const Duration(milliseconds: 450), curve: Curves.easeInOut);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 225));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      await animation;
      expect(find.text('Page 1'), findsOneWidget);
      expect(controller.page, 1);
      await tester.drag(find.byType(PageView), Offset(reverse ? -600 : 600, 0));
      await tester.pumpAndSettle();
      expect(controller.page, 0);
      expect(find.text('Page 0'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }
}
