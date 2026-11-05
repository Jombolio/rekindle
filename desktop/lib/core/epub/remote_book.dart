import 'dart:isolate';

import 'package:flutter/painting.dart';

import '../api/api_client.dart';
import '../api/media_api.dart';
import 'book_styles.dart';
import 'epub_parser.dart';
import 'reader_book.dart';

/// A book streamed from the server. Only the chapter being read and its
/// neighbours are held, and nothing is written to disk, so reading works for
/// accounts that aren't allowed to keep a copy.
class RemoteBook implements ReaderBook {
  final String mediaId;
  final String title;
  final List<({String title, String path})> chapters;
  final ApiClient _client;

  final Map<int, Future<EpubChapter>> _loaded = {};
  final Map<String, Future<String>> _stylesheets = {};

  RemoteBook._(this.mediaId, this.title, this.chapters, this._client);

  static Future<RemoteBook> open(ApiClient client, String mediaId) async {
    final manifest = await MediaApi(client).getBookManifest(mediaId);
    return RemoteBook._(mediaId, manifest.title, manifest.chapters, client);
  }

  @override
  int get chapterCount => chapters.length;

  @override
  String chapterTitle(int index) => chapters[index].title;

  @override
  int? chapterIndexOf(String path) {
    final wanted = EpubParser.normalizePath(path).toLowerCase();
    final index = chapters.indexWhere((c) => c.path.toLowerCase() == wanted);
    return index < 0 ? null : index;
  }

  @override
  Future<EpubChapter> loadChapter(int index) {
    final chapter = _fetchChapter(index);
    // Turning the page shouldn't wait on the network, and memory stays flat
    // however long the book is.
    _loaded.removeWhere((i, _) => (i - index).abs() > 1);
    if (index + 1 < chapters.length) {
      _fetchChapter(index + 1).ignore();
    }
    return chapter;
  }

  Future<EpubChapter> _fetchChapter(int index) => _loaded[index] ??= _build(index)
    ..catchError((Object _) {
      // A failure mustn't stick: the next attempt should go back to the server.
      _loaded.remove(index);
      return const EpubChapter(title: '', path: '', html: '');
    });

  Future<EpubChapter> _build(int index) async {
    final api = MediaApi(_client);
    final info = chapters[index];
    final raw = EpubParser.decodeText(await api.getBookContent(mediaId, info.path));

    final css = StringBuffer();
    for (final sheet in EpubParser.linkedStylesheets(raw)) {
      css.writeln(await _stylesheet(EpubParser.resolve(info.path, sheet)));
    }
    final cssText = css.toString();
    final path = info.path;
    final title = info.title;

    // Off the UI thread: these are regexes over what can be a very large chapter.
    return Isolate.run(() {
      final inline = EpubParser.inlineStylesheets(raw);
      return EpubChapter(
        title: title,
        path: path,
        html: EpubParser.prepareBody(raw),
        styles: BookStyles.parse('$cssText\n$inline'),
      );
    });
  }

  Future<String> _stylesheet(String path) => _stylesheets[path.toLowerCase()] ??= () async {
        try {
          return EpubParser.decodeText(await MediaApi(_client).getBookContent(mediaId, path));
        } catch (_) {
          // A book reads fine without one of its stylesheets.
          return '';
        }
      }();

  @override
  ImageProvider<Object>? imageProvider(String path) {
    final token = _client.token;
    return NetworkImage(
      MediaApi(_client).bookContentUrl(mediaId, path),
      headers: token == null ? null : {'Authorization': 'Bearer $token'},
    );
  }
}
