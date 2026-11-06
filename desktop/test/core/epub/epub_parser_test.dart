import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rekindle/core/epub/book_styles.dart';
import 'package:rekindle/core/epub/epub_parser.dart';
import 'package:rekindle/screens/epub_reader_screen.dart';
import 'package:rekindle/screens/widgets/page_tap_detector.dart';

// A 1x1 transparent PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

List<int> _epub(Map<String, Object> files) {
  final archive = Archive();
  void add(String name, List<int> data) =>
      archive.addFile(ArchiveFile(name, data.length, data));
  add('META-INF/container.xml', utf8.encode('''
<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles>
</container>'''));
  files.forEach((name, content) {
    add(name, content is String ? utf8.encode(content) : content as List<int>);
  });
  return ZipEncoder().encode(archive)!;
}

String _opf(List<String> hrefs) => '''
<package xmlns="http://www.idpf.org/2007/opf" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <metadata><dc:title>My Book</dc:title></metadata>
  <manifest>
    ${[
      for (var i = 0; i < hrefs.length; i++)
        '<item id="c$i" href="${hrefs[i]}"/>'
    ].join()}
  </manifest>
  <spine>${[
      for (var i = 0; i < hrefs.length; i++) '<itemref idref="c$i"/>'
    ].join()}</spine>
</package>''';

void main() {
  group('EpubParser.parse', () {
    test('reads chapters in spine order, skipping missing files', () {
      final book = EpubParser.parse(_epub({
        'OPS/book.opf': _opf(['b.xhtml', 'gone.xhtml', 'a.xhtml']),
        'OPS/a.xhtml': '<html><body><h1>Alpha</h1></body></html>',
        'OPS/b.xhtml': '<html><body><h2>Beta</h2></body></html>',
      }));

      expect(book.title, 'My Book');
      expect(book.chapters.map((c) => c.title), ['Beta', 'Alpha']);
    });

    test('keeps images, so a cover page is not blank', () {
      final book = EpubParser.parse(_epub({
        'OPS/book.opf': _opf(['text/cover.xhtml']),
        'OPS/text/cover.xhtml':
            '<html><body><img src="../img/Cover.PNG"/></body></html>',
        'OPS/img/Cover.PNG': _png,
      }));

      final path =
          EpubParser.resolve(book.chapters[0].path, '../img/Cover.PNG');
      expect(path, 'OPS/img/Cover.PNG');
      expect(book.imageAt(path), isNotNull);
      expect(book.imageAt('ops/IMG/cover.png'), isNotNull,
          reason: 'lookups ignore case, as books are inconsistent');
    });

    test('decodes percent-encoded hrefs', () {
      final book = EpubParser.parse(_epub({
        'OPS/book.opf': _opf(['chapter%201.xhtml']),
        'OPS/chapter 1.xhtml': '<html><body><p>x</p></body></html>',
      }));
      expect(book.chapters, hasLength(1));
      expect(book.chapterIndexOf('OPS/chapter 1.xhtml'), 0);
    });

    test('applies linked and inline stylesheets', () {
      final book = EpubParser.parse(_epub({
        'OPS/book.opf': _opf(['a.xhtml']),
        'OPS/css/main.css': '.centre { text-align: center; color: red; }',
        'OPS/a.xhtml': '''
<html><head>
  <link rel="stylesheet" href="css/main.css"/>
  <style>em { font-weight: bold; }</style>
</head><body><p class="centre">x</p></body></html>''',
      }));

      final styles = book.chapters[0].styles;
      expect(styles.stylesFor('p', ['centre']), {'text-align': 'center'});
      expect(styles.stylesFor('em', const []), {'font-weight': 'bold'});
    });

    test('throws on a file that is not an EPUB', () {
      expect(() => EpubParser.parse(utf8.encode('BOOKMOBI not a zip')),
          throwsA(anything));
    });
  });

  group('EpubParser.prepareBody', () {
    test('takes only the body, so the title is not shown as text', () {
      final body = EpubParser.prepareBody(
          '<html><head><title>T</title></head><BODY><p>x</p></BODY></html>');
      expect(body, '<p>x</p>');
    });

    test('expands self-closing tags but not void ones', () {
      expect(
        EpubParser.expandSelfClosingTags(
            '<a id="x"/><br/><img src="a/b.png"/><div/>'),
        '<a id="x"></a><br/><img src="a/b.png"/><div></div>',
      );
    });

    test('turns an image inside an SVG into an img', () {
      final body = EpubParser.prepareBody(
        '<body><svg viewBox="0 0 1 1"><image width="1" xlink:href="c.jpg"/></svg></body>',
      );
      expect(body, '<img src="c.jpg"/>');
    });

    test('removes colours but keeps other inline styling', () {
      final body = EpubParser.prepareBody(
        '<body><p style="color: black; text-align: center">x</p><font color="#000">y</font></body>',
      );
      expect(body, contains('text-align: center'));
      expect(body, isNot(contains('black')));
      expect(body, isNot(contains('#000')));
    });

    test('keeps the body class, since stylesheets can target it', () {
      expect(EpubParser.prepareBody('<body class="poem"><p>x</p></body>'),
          '<div class="poem"><p>x</p></div>');
    });
  });

  group('EpubParser.decodeText', () {
    test('honours a UTF-8 BOM', () {
      final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('é')]);
      expect(EpubParser.decodeText(bytes), 'é');
    });

    test('decodes UTF-16 by its BOM', () {
      final bytes = Uint8List.fromList([0xFF, 0xFE, 0xE9, 0x00]);
      expect(EpubParser.decodeText(bytes), 'é');
    });

    test('honours a declared Latin-1 encoding', () {
      final bytes = Uint8List.fromList([
        ...latin1.encode('<?xml version="1.0" encoding="iso-8859-1"?>'),
        0xE9,
      ]);
      expect(EpubParser.decodeText(bytes), endsWith('é'));
    });
  });

  group('BookStyles', () {
    test('class rules override tag rules', () {
      final styles = BookStyles.parse(
          'p { text-align: left; font-style: italic } .c { text-align: right }');
      expect(styles.stylesFor('p', ['c']),
          {'text-align': 'right', 'font-style': 'italic'});
    });

    test('leaves colours, fonts and spacing to the reader', () {
      final styles = BookStyles.parse(
          'p { color: #000; font-family: Arial; line-height: 3; background: red }');
      expect(styles.stylesFor('p', const []), isEmpty);
    });

    test('ignores at-rules and selectors it cannot match safely', () {
      final styles = BookStyles.parse('''
        /* comment */
        @font-face { font-weight: bold }
        a:hover { text-align: center }
        div p { text-align: right }''');
      expect(styles.stylesFor('a', const []), isEmpty);
      expect(styles.stylesFor('p', const []), {'text-align': 'right'});
    });

    test('turns paragraph indents into em spaces', () {
      expect(BookStyles.indentEms('1.2em'), 1);
      expect(BookStyles.indentEms('2em'), 2);
      expect(BookStyles.indentEms('24px'), 2);
      expect(BookStyles.indentEms('0'), 0);
      expect(BookStyles.indentEms('-1em'), 0); // Hanging indents aren't kept.
      expect(BookStyles.indentEms('5%'), 0);
      expect(BookStyles.indentEms('20em'), 4);
    });
  });

  group('isBookFinished', () {
    test('needs the end of the last chapter, not just reaching it', () {
      expect(
          isBookFinished(chapter: 9, chapterCount: 10, fraction: 0), isFalse);
      expect(
          isBookFinished(chapter: 9, chapterCount: 10, fraction: 0.5), isFalse);
      expect(
          isBookFinished(chapter: 9, chapterCount: 10, fraction: 0.98), isTrue);
    });

    test('the end of an earlier chapter is not the end of the book', () {
      expect(
          isBookFinished(chapter: 3, chapterCount: 10, fraction: 1), isFalse);
    });

    test('a single-chapter book can be in progress', () {
      expect(isBookFinished(chapter: 0, chapterCount: 1, fraction: 0), isFalse);
      expect(isBookFinished(chapter: 0, chapterCount: 1, fraction: 1), isTrue);
    });
  });

  testWidgets('renders a chapter image from inside the book', (tester) async {
    final book = EpubParser.parse(_epub({
      'OPS/book.opf': _opf(['a.xhtml']),
      'OPS/a.xhtml':
          '<html><body><p>Hello</p><img src="pic.png"/></body></html>',
      'OPS/pic.png': _png,
    }));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BookChapterView(
          book: book,
          chapter: book.chapters[0],
          textStyle: const TextStyle(fontSize: 16),
          onTapLink: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Hello', findRichText: true), findsOneWidget);
    final images = tester.widgetList<Image>(find.byType(Image));
    expect(images.map((i) => i.image).whereType<MemoryImage>(), hasLength(1));
  });

  group('inside a selectable page', () {
    Future<EpubBook> pumpPage(
      WidgetTester tester, {
      void Function()? onPageTap,
      void Function(String)? onTapLink,
      void Function(String?)? onSelected,
    }) async {
      final book = EpubParser.parse(_epub({
        'OPS/book.opf': _opf(['a.xhtml', 'b.xhtml']),
        'OPS/a.xhtml':
            '<html><body><p>Hello wonderful world</p><a href="b.xhtml">note</a></body></html>',
        'OPS/b.xhtml': '<html><body><p>x</p></body></html>',
      }));
      // Wired the way the reader wires it.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PageTapDetector(
            onTap: (_) => onPageTap?.call(),
            child: SelectionArea(
              onSelectionChanged: (c) => onSelected?.call(c?.plainText),
              child: BookChapterView(
                book: book,
                chapter: book.chapters[0],
                textStyle: const TextStyle(fontSize: 16),
                onTapLink: onTapLink ?? (_) {},
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return book;
    }

    testWidgets('a tap on the text still reaches the page', (tester) async {
      var taps = 0;
      await pumpPage(tester, onPageTap: () => taps++);
      await tester.tap(find.textContaining('Hello', findRichText: true));
      await tester.pump(const Duration(milliseconds: 400));
      expect(taps, 1);
    });

    testWidgets('a double-click selects, and is not a tap', (tester) async {
      var taps = 0;
      await pumpPage(tester, onPageTap: () => taps++);
      final at =
          tester.getTopLeft(find.textContaining('Hello', findRichText: true)) +
              const Offset(12, 10);
      final gesture =
          await tester.startGesture(at, kind: PointerDeviceKind.mouse);
      await tester.pump();
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.down(at);
      await tester.pump();
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(taps, 0);
    });

    testWidgets('dragging across text is not a tap', (tester) async {
      var taps = 0;
      await pumpPage(tester, onPageTap: () => taps++);
      final at =
          tester.getTopLeft(find.textContaining('Hello', findRichText: true)) +
              const Offset(4, 10);
      final gesture =
          await tester.startGesture(at, kind: PointerDeviceKind.mouse);
      await tester.pump();
      await gesture.moveBy(const Offset(120, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(taps, 0);
    });

    testWidgets('links still work', (tester) async {
      String? tapped;
      await pumpPage(tester, onTapLink: (url) => tapped = url);
      await tester.tap(find.textContaining('note', findRichText: true));
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expect(tapped, isNotNull);
    });

    testWidgets('double-clicking selects a word', (tester) async {
      String? selected;
      await pumpPage(tester, onSelected: (text) => selected = text);
      final at =
          tester.getTopLeft(find.textContaining('Hello', findRichText: true)) +
              const Offset(12, 10);
      final gesture =
          await tester.startGesture(at, kind: PointerDeviceKind.mouse);
      await tester.pump();
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.down(at);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expect(selected?.trim(), 'Hello');
    });
  });

  testWidgets('tapping a link reports its address in the book', (tester) async {
    final book = EpubParser.parse(_epub({
      'OPS/book.opf': _opf(['a.xhtml', 'b.xhtml']),
      'OPS/a.xhtml': '<html><body><a href="b.xhtml#n1">note</a></body></html>',
      'OPS/b.xhtml': '<html><body><p>x</p></body></html>',
    }));
    String? tapped;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BookChapterView(
          book: book,
          chapter: book.chapters[0],
          textStyle: const TextStyle(fontSize: 16),
          onTapLink: (url) => tapped = url,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('note', findRichText: true));
    await tester.pumpAndSettle();

    final uri = Uri.parse(tapped!);
    expect(uri.path, '/OPS/b.xhtml');
    expect(book.chapterIndexOf(Uri.decodeFull(uri.path)), 1);
  });

  testWidgets('indents paragraphs the book indents', (tester) async {
    final book = EpubParser.parse(_epub({
      'OPS/book.opf': _opf(['a.xhtml']),
      'OPS/a.xhtml': '<html><head><style>p { margin: 0; text-indent: 1.5em }'
          '.first { text-indent: 0 }</style></head><body>'
          '<p class="first">Opening.</p><p>Following.</p></body></html>',
    }));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BookChapterView(
          book: book,
          chapter: book.chapters[0],
          textStyle: const TextStyle(fontSize: 16),
          onTapLink: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('  Following.', findRichText: true),
        findsOneWidget);
    expect(find.textContaining(' Opening.', findRichText: true), findsNothing);
  });

  testWidgets('links take the text colour, not the app theme', (tester) async {
    final book = EpubParser.parse(_epub({
      'OPS/book.opf': _opf(['a.xhtml']),
      'OPS/a.xhtml':
          '<html><body><p><a href="a.xhtml">Chapter 1</a></p></body></html>',
    }));
    const ink = Color(0xFF3B2C1A);

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.purple)),
      home: Scaffold(
        body: BookChapterView(
          book: book,
          chapter: book.chapters[0],
          textStyle: const TextStyle(fontSize: 16, color: ink),
          onTapLink: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final text = tester.widget<RichText>(
        find.textContaining('Chapter 1', findRichText: true).first);
    final styles = <TextStyle>[];
    text.text.visitChildren((span) {
      if (span is TextSpan && (span.text?.contains('Chapter') ?? false)) {
        styles.add(span.style!);
      }
      return true;
    });
    final link = styles.isEmpty ? text.text.style! : styles.first;
    expect(link.color, ink);
    expect(link.decoration, isNot(TextDecoration.underline));
  });
}
