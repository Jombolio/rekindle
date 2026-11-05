import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/painting.dart';
import 'package:xml/xml.dart';

import 'book_styles.dart';
import 'reader_book.dart';

class EpubChapter {
  final String title;

  /// Path of this chapter inside the EPUB; links and images resolve against it.
  final String path;

  /// The chapter's body markup, cleaned up for the reader.
  final String html;
  final BookStyles styles;

  const EpubChapter({
    required this.title,
    required this.path,
    required this.html,
    this.styles = BookStyles.empty,
  });
}

class EpubBook implements ReaderBook {
  final String title;
  final List<EpubChapter> chapters;

  /// Images in the book, by lower-cased path inside the EPUB.
  final Map<String, Uint8List> images;

  const EpubBook({
    required this.title,
    required this.chapters,
    this.images = const {},
  });

  Uint8List? imageAt(String path) =>
      images[EpubParser.normalizePath(path).toLowerCase()];

  @override
  int get chapterCount => chapters.length;

  @override
  String chapterTitle(int index) => chapters[index].title;

  @override
  Future<EpubChapter> loadChapter(int index) async => chapters[index];

  @override
  ImageProvider<Object>? imageProvider(String path) {
    final bytes = imageAt(path);
    return bytes == null ? null : MemoryImage(bytes);
  }

  @override
  int? chapterIndexOf(String path) {
    final wanted = EpubParser.normalizePath(path).toLowerCase();
    final index =
        chapters.indexWhere((c) => c.path.toLowerCase() == wanted);
    return index < 0 ? null : index;
  }
}

class EpubParser {
  static final _imageExtensions = RegExp(
    r'\.(png|jpe?g|gif|webp|bmp)$',
    caseSensitive: false,
  );

  /// Whether the file at [path] is a ZIP container, which every EPUB is. Copies
  /// of MOBI files downloaded by older versions are not.
  static Future<bool> isEpubFile(String path) async {
    final file = File(path);
    if (!await file.exists()) return false;
    final head = await file.openRead(0, 2).expand((b) => b).toList();
    return head.length == 2 && head[0] == 0x50 && head[1] == 0x4B;
  }

  /// Parse an EPUB file from raw bytes.
  static EpubBook parse(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);

    // Case-insensitive, since some EPUBs have inconsistent casing.
    final entries = <String, ArchiveFile>{
      for (final f in archive.files)
        if (f.isFile) normalizePath(f.name).toLowerCase(): f,
    };

    final container = _readXml(entries, 'META-INF/container.xml');
    final opfPath = container
        .findAllElements('rootfile')
        .first
        .getAttribute('full-path')!;
    final opf = _readXml(entries, opfPath);

    final title = opf
            .findAllElements('dc:title')
            .firstOrNull
            ?.innerText ??
        'Unknown';

    // Build id→href manifest
    final manifest = <String, String>{};
    for (final item in opf.findAllElements('item')) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      if (id != null && href != null) manifest[id] = href;
    }

    final spineItems = opf
        .findAllElements('itemref')
        .map((e) => e.getAttribute('idref'))
        .whereType<String>()
        .toList();

    final stylesheets = <String, String>{};
    final chapters = <EpubChapter>[];
    for (final idref in spineItems) {
      final href = manifest[idref];
      if (href == null) continue;

      final path = resolve(opfPath, href);
      final entry = entries[path.toLowerCase()];
      if (entry == null) continue;

      final raw = decodeText(_bytesOf(entry));
      final css = StringBuffer();
      for (final sheet in linkedStylesheets(raw)) {
        final sheetPath = resolve(path, sheet).toLowerCase();
        final text = stylesheets[sheetPath] ??= entries[sheetPath] == null
            ? ''
            : decodeText(_bytesOf(entries[sheetPath]!));
        css.writeln(text);
      }
      css.writeln(inlineStylesheets(raw));

      chapters.add(EpubChapter(
        title: extractTitle(raw) ?? _fileName(path),
        path: path,
        html: prepareBody(raw),
        styles: BookStyles.parse(css.toString()),
      ));
    }

    final images = <String, Uint8List>{
      for (final e in entries.entries)
        if (_imageExtensions.hasMatch(e.key)) e.key: _bytesOf(e.value),
    };

    return EpubBook(title: title, chapters: chapters, images: images);
  }

  static Uint8List _bytesOf(ArchiveFile file) =>
      Uint8List.fromList(file.content as List<int>);

  static String _fileName(String path) => path.split('/').last;

  /// Resolves an href found in the document at [fromPath]. Hrefs are URIs:
  /// percent-encoded and possibly carrying a #fragment, while paths in the
  /// archive are raw.
  static String resolve(String fromPath, String href) {
    var target = href.split('#').first;
    try {
      target = Uri.decodeFull(target);
    } catch (_) {
      // Malformed escape: use it as written.
    }
    if (target.startsWith('/')) return normalizePath(target);
    final slash = fromPath.lastIndexOf('/');
    final dir = slash < 0 ? '' : fromPath.substring(0, slash + 1);
    return normalizePath('$dir$target');
  }

  /// Resolves ./ and ../ segments so hrefs and archive paths compare equal.
  static String normalizePath(String path) {
    final parts = <String>[];
    for (final segment in path.replaceAll('\\', '/').split('/')) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') {
        if (parts.isNotEmpty) parts.removeLast();
      } else {
        parts.add(segment);
      }
    }
    return parts.join('/');
  }

  static XmlDocument _readXml(Map<String, ArchiveFile> entries, String path) {
    final entry = entries[normalizePath(path).toLowerCase()];
    if (entry == null) throw StateError('EPUB missing: $path');
    return XmlDocument.parse(decodeText(_bytesOf(entry)));
  }

  /// Decodes book text using its BOM or XML declaration. Most books are UTF-8,
  /// but older ones are often UTF-16 or Latin-1.
  static String decodeText(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3), allowMalformed: true);
    }
    if (bytes.length >= 2) {
      if (bytes[0] == 0xFF && bytes[1] == 0xFE) return _utf16(bytes, true);
      if (bytes[0] == 0xFE && bytes[1] == 0xFF) return _utf16(bytes, false);
    }

    final head = latin1.decode(
      bytes.length > 200 ? bytes.sublist(0, 200) : bytes,
    );
    final declared = RegExp(r'''encoding\s*=\s*["']([\w-]+)["']''')
        .firstMatch(head)
        ?.group(1)
        ?.toLowerCase();
    if (declared == 'iso-8859-1' ||
        declared == 'latin1' ||
        declared == 'windows-1252') {
      return latin1.decode(bytes);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  static String _utf16(Uint8List bytes, bool littleEndian) {
    final units = <int>[];
    for (var i = 2; i + 1 < bytes.length; i += 2) {
      units.add(littleEndian
          ? bytes[i] | (bytes[i + 1] << 8)
          : (bytes[i] << 8) | bytes[i + 1]);
    }
    return String.fromCharCodes(units);
  }

  /// The chapter's title: its first heading, else its `<title>`. Many books
  /// repeat the book's name in every `<title>`, so a heading is the better guide.
  static String? extractTitle(String html) {
    String? clean(String? raw) {
      final text = raw?.replaceAll(RegExp(r'<[^>]+>'), '').trim();
      return text == null || text.isEmpty ? null : text;
    }

    final heading = RegExp(
      r'<h[1-3]\b[^>]*>(.*?)</h[1-3]\s*>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(html);
    final title = RegExp(
      r'<title[^>]*>(.*?)</title>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(html);
    return clean(heading?.group(1)) ?? clean(title?.group(1));
  }

  /// Hrefs of the stylesheets a chapter links to.
  static List<String> linkedStylesheets(String html) {
    final links = RegExp(r'<link\b[^>]*>', caseSensitive: false)
        .allMatches(html)
        .map((m) => m.group(0)!);
    final href = RegExp(r'''href\s*=\s*["']([^"']+)["']''', caseSensitive: false);
    return [
      for (final link in links)
        if (link.toLowerCase().contains('stylesheet'))
          if (href.firstMatch(link)?.group(1) case final String h) h,
    ];
  }

  static String inlineStylesheets(String html) => RegExp(
        r'<style\b[^>]*>(.*?)</style\s*>',
        caseSensitive: false,
        dotAll: true,
      ).allMatches(html).map((m) => m.group(1)!).join('\n');

  /// Turns a chapter document into the markup the reader renders: just the body,
  /// in a form the HTML widget understands, without colours that would fight the
  /// reader's theme.
  static String prepareBody(String html) {
    final match = RegExp(
      r'<body\b([^>]*)>(.*)</body\s*>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(html);
    var body = match?.group(2) ?? html;

    // The widget has no SVG support, and covers are often an image in an SVG.
    body = body.replaceAllMapped(
      RegExp(
        r'<svg\b[^>]*>.*?</svg\s*>',
        caseSensitive: false,
        dotAll: true,
      ),
      (m) {
        final href = RegExp(
          r'''<image\b[^>]*?href\s*=\s*["']([^"']+)["']''',
          caseSensitive: false,
          dotAll: true,
        ).firstMatch(m.group(0)!)?.group(1);
        return href == null ? '' : '<img src="$href"/>';
      },
    );

    body = expandSelfClosingTags(body);
    body = stripThemeColours(body);

    final bodyClass = RegExp(
      r'''class\s*=\s*["']([^"']*)["']''',
      caseSensitive: false,
    ).firstMatch(match?.group(1) ?? '')?.group(1);
    return bodyClass == null || bodyClass.isEmpty
        ? body
        : '<div class="$bodyClass">$body</div>';
  }

  /// `<a id="x"/>` is valid XHTML, but an HTML parser reads it as an unclosed
  /// `<a>` that swallows what follows.
  static String expandSelfClosingTags(String html) => html.replaceAllMapped(
        RegExp(r'<([a-zA-Z][\w:-]*)((?:[^<>"]|"[^"]*")*?)/>'),
        (m) {
          final tag = m.group(1)!;
          const voidTags = {'img', 'br', 'hr', 'input', 'meta', 'link', 'col'};
          return voidTags.contains(tag.toLowerCase())
              ? m.group(0)!
              : '<$tag${m.group(2)}></$tag>';
        },
      );

  /// Removes colours and backgrounds set in the markup. They're usually black
  /// text from the publisher, which would be unreadable on the dark theme.
  static String stripThemeColours(String html) => html
      .replaceAllMapped(
        RegExp(r'''style\s*=\s*(["'])(.*?)\1''', caseSensitive: false),
        (m) {
          final kept = m
              .group(2)!
              .split(';')
              .where((d) => !RegExp(
                    r'^\s*(color|background(-color)?)\s*:',
                    caseSensitive: false,
                  ).hasMatch(d))
              .join(';');
          return 'style=${m.group(1)}$kept${m.group(1)}';
        },
      )
      .replaceAll(
        RegExp(
          r'''\s(?:color|bgcolor)\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)''',
          caseSensitive: false,
        ),
        '',
      );
}
