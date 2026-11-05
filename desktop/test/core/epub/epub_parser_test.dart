import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rekindle/core/epub/book_styles.dart';
import 'package:rekindle/core/epub/epub_parser.dart';
import 'package:rekindle/screens/epub_reader_screen.dart';

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
    ${[for (var i = 0; i < hrefs.length; i++) '<item id="c$i" href="${hrefs[i]}"/>'].join()}
  </manifest>
  <spine>${[for (var i = 0; i < hrefs.length; i++) '<itemref idref="c$i"/>'].join()}</spine>
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

      final path = EpubParser.resolve(book.chapters[0].path, '../img/Cover.PNG');
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
        EpubParser.expandSelfClosingTags('<a id="x"/><br/><img src="a/b.png"/><div/>'),
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
  });

  group('isBookFinished', () {
    test('needs the end of the last chapter, not just reaching it', () {
      expect(isBookFinished(chapter: 9, chapterCount: 10, fraction: 0), isFalse);
      expect(isBookFinished(chapter: 9, chapterCount: 10, fraction: 0.5), isFalse);
      expect(isBookFinished(chapter: 9, chapterCount: 10, fraction: 0.98), isTrue);
    });

    test('the end of an earlier chapter is not the end of the book', () {
      expect(isBookFinished(chapter: 3, chapterCount: 10, fraction: 1), isFalse);
    });

    test('a single-chapter book can be in progress', () {
      expect(isBookFinished(chapter: 0, chapterCount: 1, fraction: 0), isFalse);
      expect(isBookFinished(chapter: 0, chapterCount: 1, fraction: 1), isTrue);
    });
  });

  testWidgets('renders a chapter image from inside the book', (tester) async {
    final book = EpubParser.parse(_epub({
      'OPS/book.opf': _opf(['a.xhtml']),
      'OPS/a.xhtml': '<html><body><p>Hello</p><img src="pic.png"/></body></html>',
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
}
