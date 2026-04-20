import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

class EpubChapter {
  final String title;
  final String html;

  const EpubChapter({required this.title, required this.html});
}

class EpubBook {
  final String title;
  final List<EpubChapter> chapters;

  const EpubBook({required this.title, required this.chapters});
}

class EpubParser {
  /// Parse an EPUB file from raw bytes.
  static EpubBook parse(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);

    final container = _readXml(archive, 'META-INF/container.xml');
    final opfPath = container
        .findAllElements('rootfile')
        .first
        .getAttribute('full-path')!;

    final opfDir = opfPath.contains('/')
        ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1)
        : '';

    final opf = _readXml(archive, opfPath);

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

    // Spine order
    final spineItems = opf
        .findAllElements('itemref')
        .map((e) => e.getAttribute('idref'))
        .whereType<String>()
        .toList();

    final chapters = <EpubChapter>[];
    for (final idref in spineItems) {
      final href = manifest[idref];
      if (href == null) continue;

      final fullPath = '$opfDir$href';
      final entry = _findEntry(archive, fullPath);
      if (entry == null) continue;

      final html = utf8.decode(entry.content as List<int>, allowMalformed: true);
      final chapterTitle = _extractTitle(html) ?? href;
      chapters.add(EpubChapter(title: chapterTitle, html: html));
    }

    return EpubBook(title: title, chapters: chapters);
  }

  static XmlDocument _readXml(Archive archive, String path) {
    final entry = _findEntry(archive, path);
    if (entry == null) throw StateError('EPUB missing: $path');
    final content = utf8.decode(entry.content as List<int>, allowMalformed: true);
    return XmlDocument.parse(content);
  }

  static ArchiveFile? _findEntry(Archive archive, String path) {
    // Case-insensitive lookup since some EPUBs have inconsistent casing
    final lower = path.toLowerCase();
    for (final f in archive.files) {
      if (f.name.toLowerCase() == lower) return f;
    }
    return null;
  }

  static String? _extractTitle(String html) {
    final titleMatch = RegExp(
      r'<title[^>]*>(.*?)</title>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(html);
    final raw = titleMatch?.group(1)?.trim();
    if (raw == null || raw.isEmpty) return null;
    // Strip any inner tags
    return raw.replaceAll(RegExp(r'<[^>]+>'), '').trim();
  }
}
