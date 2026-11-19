import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

/// The attribute that ties each piece of a chapter's text to the sentence it
/// belongs to, so the one being read can be picked out on the page.
const sentenceAttribute = 'data-ra';

/// A chapter's HTML with every sentence marked, and the sentences to speak.
class MarkedChapter {
  /// The chapter, with each run of a sentence's text in a
  /// `<span data-ra="n">`. A sentence crossing an inline element, such as an
  /// italicised phrase, is several spans with the same number. Spans carry no
  /// style, so the chapter lays out exactly as before.
  final String html;

  /// The sentences in reading order, as plain text. A sentence's number is its
  /// index here.
  final List<String> sentences;

  /// How far through the chapter's text each sentence starts, from 0 to 1, to
  /// find where to begin reading from a position.
  final List<double> starts;

  const MarkedChapter(this.html, this.sentences, this.starts);

  /// Whether sentence [i] has anything to say: a row of asterisks marking a
  /// scene break is a sentence on the page, but nothing to read aloud.
  bool speakable(int i) => RegExp(r'[\p{L}\p{N}]', unicode: true)
      .hasMatch(sentences[i]);

  /// The sentence under [fraction] of the way through the chapter: the one it
  /// falls within. Reading from a page starts there, so a sentence begun on the
  /// page before and finished on this one is read whole, not skipped.
  int sentenceAt(double fraction) {
    var found = 0;
    for (var i = 0; i < starts.length; i++) {
      if (starts[i] <= fraction + 1e-9) found = i;
    }
    return found;
  }

  /// The sentence at a spot on the page, found by its text, since the page
  /// keeps no link back to the marked HTML. [after] is the text from the spot
  /// on and [before] the text just ahead of it, which tells apart words that
  /// appear more than once. Where the text is still in the chapter more than
  /// once, the copy nearest [near] of the way through wins. Null when it isn't
  /// found at all.
  int? sentenceOfText({
    String before = '',
    required String after,
    double near = 0,
  }) {
    // Case is folded because a style can capitalise text on the page.
    String fold(String s) => s
        .replaceAll('￼', ' ') // Pictures inline in the text.
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();

    final begins = <int>[];
    final all = StringBuffer();
    for (final sentence in sentences) {
      if (all.isNotEmpty) all.write(' ');
      begins.add(all.length);
      all.write(sentence.toLowerCase());
    }
    final text = all.toString();

    final head = fold(before);
    final tail = fold(after);
    if (tail.isEmpty) return null;
    final word = tail.split(' ').first;
    // Shorter and shorter, in case the page shows something the text doesn't,
    // such as a list's bullet.
    final attempts = <(String, int)>[
      if (head.isNotEmpty) ('$head $tail', head.length + 1),
      (tail, 0),
      if (tail.length > 30) (tail.substring(0, 30), 0),
      if (word != tail) (word, 0),
    ];

    for (final (needle, lead) in attempts) {
      int? best;
      var distance = double.infinity;
      for (var at = text.indexOf(needle);
          at >= 0;
          at = text.indexOf(needle, at + 1)) {
        var i = 0;
        while (i + 1 < begins.length && begins[i + 1] <= at + lead) {
          i++;
        }
        final d = ((i < starts.length ? starts[i] : 1.0) - near).abs();
        if (d < distance) {
          best = i;
          distance = d;
        }
      }
      if (best != null) return best;
    }
    return null;
  }
}

/// Elements that end whatever sentence is open: a heading or a paragraph is
/// never read as part of the one before it, punctuated or not.
const _blocks = {
  'address', 'article', 'aside', 'blockquote', 'br', 'dd', 'div', 'dl', 'dt',
  'figcaption', 'figure', 'footer', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
  'header', 'hr', 'li', 'nav', 'ol', 'p', 'pre', 'section', 'table', 'td',
  'th', 'tr', 'ul',
};

/// Elements whose text is not read: code and styling, ruby annotations, and
/// pictures.
const _silent = {'script', 'style', 'rt', 'rp', 'svg', 'math', 'head', 'title'};

/// Words that end in a full stop without ending the sentence.
final _abbreviation = RegExp(
  r'(?:^|[\s(“"‘])(?:Mr|Mrs|Ms|Mx|Dr|Prof|St|Jr|Sr|Mt|No|vs|etc|viz|cf|'
  r'Gen|Col|Capt|Lt|Sgt|Rev|Hon|Fr|[A-HJ-Z])\.$',
);

/// The end of a sentence: closing punctuation, any closing quotes or brackets,
/// then space or the end of the text.
final _end = RegExp(r'''[.!?…]+["'”’)\]]*(?=\s|$)''');

/// Marks the sentences of a chapter's HTML. See [MarkedChapter].
MarkedChapter markSentences(String source) {
  final fragment = html.parseFragment(source);
  final sentences = <String>[];
  final offsets = <int>[];
  final open = StringBuffer();
  var text = 0;

  void close() {
    final sentence = open.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    open.clear();
    if (sentence.isEmpty) return;
    sentences.add(sentence);
  }

  void startIfNew() {
    if (open.toString().trim().isEmpty && offsets.length == sentences.length) {
      offsets.add(text);
    }
  }

  void markText(dom.Text node) {
    final value = node.data;
    final pieces = <dom.Node>[];
    var at = 0;
    void emit(String piece, {required bool ends}) {
      if (piece.isEmpty) return;
      if (piece.trim().isEmpty) {
        pieces.add(dom.Text(piece));
        open.write(piece);
        text += piece.length;
        return;
      }
      startIfNew();
      pieces.add(dom.Element.tag('span')
        ..attributes[sentenceAttribute] = '${sentences.length}'
        ..append(dom.Text(piece)));
      open.write(piece);
      text += piece.length;
      if (ends) close();
    }

    for (final m in _end.allMatches(value)) {
      final upTo = value.substring(at, m.end);
      // "Mr." and an initial end in a full stop but carry on the sentence.
      final before = '$open${value.substring(at, m.end)}'.trimRight();
      if (m.group(0)!.startsWith('.') &&
          !m.group(0)!.contains(RegExp(r'[!?…]')) &&
          _abbreviation.hasMatch(before)) {
        continue;
      }
      emit(upTo, ends: true);
      at = m.end;
    }
    emit(value.substring(at), ends: false);

    final parent = node.parentNode!;
    for (final piece in pieces) {
      parent.insertBefore(piece, node);
    }
    node.remove();
  }

  void walk(dom.Node node) {
    if (node is dom.Text) {
      markText(node);
      return;
    }
    if (node is dom.Element) {
      final tag = node.localName ?? '';
      if (_silent.contains(tag)) return;
      final block = _blocks.contains(tag);
      if (block) close();
      for (final child in [...node.nodes]) {
        walk(child);
      }
      if (block) close();
      return;
    }
    for (final child in [...node.nodes]) {
      walk(child);
    }
  }

  walk(fragment);
  close();

  final total = text == 0 ? 1 : text;
  return MarkedChapter(
    fragment.outerHtml,
    sentences,
    [for (final o in offsets.take(sentences.length)) o / total],
  );
}
