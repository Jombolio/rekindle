import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rekindle/screens/widgets/release_notes.dart';

void main() {
  group('ReleaseNotes.toHtml', () {
    test('converts the Markdown our release notes use', () {
      final html = ReleaseNotes.toHtml('''
**Pre-release.** A beta.

## New since beta.1

- **Updates fall back to GitHub.** Uses `--update`, see [Updating](https://git.jombo.uk/Jombo/rekindle/wiki).
- Second item
''');

      expect(html, contains('<strong>Pre-release.</strong>'));
      expect(html, contains('<h2>New since beta.1</h2>'));
      expect(html, contains('<li><strong>Updates fall back to GitHub.</strong>'));
      expect(html, contains('<code>--update</code>'));
      expect(html, contains('<a href="https://git.jombo.uk/Jombo/rekindle/wiki">Updating</a>'));
      expect(html, isNot(contains('##')));
      expect(html, isNot(contains('**')));
    });

    test('renders every shipped release notes file without raw Markdown', () {
      final dir = Directory('../release-notes');
      if (!dir.existsSync()) return; // running outside the repository
      for (final f in dir.listSync().whereType<File>()) {
        final html = ReleaseNotes.toHtml(f.readAsStringSync());
        expect(html, isNot(contains('**')), reason: f.path);
        expect(RegExp(r'^#+ ', multiLine: true).hasMatch(html), isFalse,
            reason: f.path);
      }
    });
  });

  testWidgets('shows formatted text, not Markdown syntax', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ReleaseNotes('## Fixes\n\n- **Bold** fix with `code`'),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Fixes', findRichText: true), findsWidgets);
    expect(find.textContaining('Bold', findRichText: true), findsWidgets);
    expect(find.textContaining('##', findRichText: true), findsNothing);
    expect(find.textContaining('**', findRichText: true), findsNothing);
  });
}
