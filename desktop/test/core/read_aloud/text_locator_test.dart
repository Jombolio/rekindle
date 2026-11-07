import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:rekindle/core/read_aloud/sentences.dart';
import 'package:rekindle/core/read_aloud/text_locator.dart';

void main() {
  const highlight = Color.fromRGBO(20, 30, 40, 0.2);
  const css = 'rgba(20, 30, 40, 0.200)';

  Widget chapter(MarkedChapter marked, int sentence, GlobalKey key) =>
      MaterialApp(
        home: SingleChildScrollView(
          child: SizedBox(
            key: key,
            width: 300,
            child: HtmlWidget(
              marked.html,
              buildAsync: false,
              rebuildTriggers: [sentence],
              customStylesBuilder: (e) =>
                  e.attributes[sentenceAttribute] == '$sentence'
                      ? {'background-color': css}
                      : null,
            ),
          ),
        ),
      );

  testWidgets('finds the sentence being read, and follows it down the page',
      (tester) async {
    final marked = markSentences(
        '<p>The first paragraph. Its second sentence.</p>'
        '${'<p>Filler text that takes up some room on the page.</p>' * 20}'
        '<p>The <em>last</em> paragraph.</p>');
    final key = GlobalKey();
    double? topOf(int sentence) =>
        highlightTop(key.currentContext!.findRenderObject()!, highlight);

    await tester.pumpWidget(chapter(marked, 0, key));
    final first = topOf(0);
    expect(first, isNotNull, reason: 'the CSS background reaches the text');
    expect(first, lessThan(30));

    final last = marked.sentences.length - 1;
    expect(marked.sentences[last], 'The last paragraph.');
    await tester.pumpWidget(chapter(marked, last, key));
    expect(topOf(last), greaterThan(first! + 300));
  });

  testWidgets('finds nothing when nothing is highlighted', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(chapter(markSentences('<p>Hello.</p>'), 5, key));
    expect(highlightTop(key.currentContext!.findRenderObject()!, highlight),
        isNull);
  });
}
