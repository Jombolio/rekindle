import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rekindle/core/api/api_client.dart';
import 'package:rekindle/core/epub/remote_book.dart';

/// Answers book requests from a map of path to content.
class _FakeServer implements HttpClientAdapter {
  final Map<String, String> files;
  final List<String> requested = [];
  int failuresLeft = 0;

  _FakeServer(this.files);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.endsWith('/book/manifest')) {
      return ResponseBody.fromString(
        jsonEncode({
          'title': 'The Book',
          'chapters': [
            {'title': 'One', 'path': 'OPS/a b.xhtml'},
            {'title': 'Two', 'path': 'OPS/two.xhtml'},
            {'title': 'Three', 'path': 'OPS/three.xhtml'},
          ],
        }),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }
    requested.add(options.path);
    final path = Uri.decodeFull(options.path.split('/book/content/').last);
    if (failuresLeft > 0) {
      failuresLeft--;
      return ResponseBody.fromString('', 500);
    }
    final file = files[path];
    if (file == null) return ResponseBody.fromString('', 404);
    return ResponseBody.fromBytes(utf8.encode(file), 200);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _FakeServer server;
  late RemoteBook book;

  setUp(() async {
    server = _FakeServer({
      'OPS/a b.xhtml':
          '<html><head><link rel="stylesheet" href="css/s.css"/></head><body><p class="c">one</p></body></html>',
      'OPS/two.xhtml': '<html><body><p>two</p></body></html>',
      'OPS/three.xhtml': '<html><body><p>three</p></body></html>',
      'OPS/css/s.css': '.c { text-align: center }',
    });
    final client = ApiClient.anonymous(baseUrl: 'http://server.test/');
    client.dio.httpClientAdapter = server;
    book = await RemoteBook.open(client, 'm1');
  });

  test('knows the chapters without fetching any of them', () {
    expect(book.title, 'The Book');
    expect(book.chapterCount, 3);
    expect(book.chapterTitle(1), 'Two');
    expect(book.chapterIndexOf('ops/TWO.xhtml'), 1);
    expect(book.chapterIndexOf('OPS/none.xhtml'), isNull);
    expect(server.requested, isEmpty);
  });

  test('fetches a chapter with its stylesheet, encoding the path', () async {
    final chapter = await book.loadChapter(0);

    expect(chapter.html, '<p class="c">one</p>');
    expect(chapter.styles.stylesFor('p', ['c']), {'text-align': 'center'});
    expect(server.requested.first, contains('OPS/a%20b.xhtml'));
  });

  test('only ever reads ahead by one chapter', () async {
    await book.loadChapter(0);
    await book.loadChapter(1);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    // Opening chapter 1 fetched it and chapter 2. Chapter 3 waited for chapter 2.
    expect(
      server.requested.where((p) => p.contains('.xhtml')).length,
      3,
    );
  });

  test('opening the first chapter does not fetch the whole book', () async {
    await book.loadChapter(0);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(server.requested.where((p) => p.contains('three')), isEmpty);
  });

  test('a failed chapter can be retried', () async {
    server.failuresLeft = 2;
    await expectLater(book.loadChapter(1), throwsA(anything));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    server.failuresLeft = 0;
    final chapter = await book.loadChapter(1);
    expect(chapter.html, '<p>two</p>');
  });

  test('images load from the server with the session token', () async {
    final client = ApiClient.anonymous(baseUrl: 'http://server.test');
    final provider = (await RemoteBook.open(
      client..dio.httpClientAdapter = server,
      'm1',
    ))
        .imageProvider('OPS/my pic.png') as NetworkImage;

    expect(provider.url,
        'http://server.test/api/media/m1/book/content/OPS/my%20pic.png');
  });
}
