import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:rekindle/core/read_aloud/sentences.dart';

void main() {
  test('splits prose and dialogue into sentences', () {
    final marked = markSentences(
      '<p>It is a truth universally acknowledged. "My dear Mr. Bennet," said '
      'his lady, "have you heard?" Mr. Bennet replied that he had not.</p>',
    );
    expect(marked.sentences, [
      'It is a truth universally acknowledged.',
      '"My dear Mr. Bennet," said his lady, "have you heard?"',
      'Mr. Bennet replied that he had not.',
    ]);
  });

  test('titles and initials do not end a sentence, but "I" does', () {
    final marked = markSentences(
      '<p>Dr. Watson met J. R. Smith at St. Paul’s. So did I. Then we left.</p>',
    );
    expect(marked.sentences, [
      'Dr. Watson met J. R. Smith at St. Paul’s.',
      'So did I.',
      'Then we left.',
    ]);
  });

  test('a heading or paragraph always ends a sentence', () {
    final marked = markSentences(
      '<h1>Chapter One</h1><p>No full stop here</p><p>Next one.</p>',
    );
    expect(marked.sentences, ['Chapter One', 'No full stop here', 'Next one.']);
  });

  test('a sentence across inline elements keeps one number', () {
    final marked =
        markSentences('<p>She was <em>very</em> tired. He was not.</p>');
    expect(marked.sentences, ['She was very tired.', 'He was not.']);
    final spans = html
        .parseFragment(marked.html)
        .querySelectorAll('span[$sentenceAttribute]');
    // "She was ", "very" and " tired. " are all sentence 0.
    expect(
      spans.map((s) => (s.attributes[sentenceAttribute], s.text.trim())),
      [('0', 'She was'), ('0', 'very'), ('0', 'tired.'), ('1', 'He was not.')],
    );
  });

  test('only spans are added: the text and its elements are unchanged', () {
    const source = '<div class="c"><p id="x">A cat. <a href="#n">A dog.</a>'
        '</p><img src="i.png"><p>An end.</p></div>';
    final marked = markSentences(source);
    final before = html.parseFragment(source);
    final after = html.parseFragment(marked.html);
    expect(after.text, before.text);
    for (final span in after.querySelectorAll('span[$sentenceAttribute]')) {
      span.replaceWith(span.nodes.first.clone(true));
    }
    expect(after.querySelector('p#x'), isNotNull);
    expect(after.querySelector('a[href="#n"]'), isNotNull);
    expect(after.querySelector('img[src="i.png"]'), isNotNull);
    expect(marked.sentences, ['A cat.', 'A dog.', 'An end.']);
  });

  test('scripts and styles are not read', () {
    final marked = markSentences(
      '<style>p { color: red; }</style><p>Read this.</p><script>no();</script>',
    );
    expect(marked.sentences, ['Read this.']);
  });

  test('a scene break is a sentence on the page, but nothing to say', () {
    final marked = markSentences('<p>One.</p><p>* * *</p><p>Two.</p>');
    expect(marked.sentences, ['One.', '* * *', 'Two.']);
    expect([for (var i = 0; i < 3; i++) marked.speakable(i)],
        [true, false, true]);
  });

  test('starts find where to begin reading from a position', () {
    final marked = markSentences('<p>Aaaa. Bbbb. Cccc. Dddd.</p>');
    expect(marked.starts.length, 4);
    expect(marked.starts.first, 0);
    for (var i = 1; i < 4; i++) {
      expect(marked.starts[i], greaterThan(marked.starts[i - 1]));
    }
    expect(marked.sentenceAt(0), 0);
    expect(marked.sentenceAt(0.5), 2);
    expect(marked.sentenceAt(1), 3);
  });
}
