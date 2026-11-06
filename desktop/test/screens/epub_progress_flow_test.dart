import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rekindle/core/api/api_client.dart';
import 'package:rekindle/core/db/local_db.dart';
import 'package:rekindle/core/db/local_db_provider.dart';
import 'package:rekindle/core/storage/prefs.dart';
import 'package:rekindle/providers/auth_provider.dart';
import 'package:rekindle/providers/connectivity_provider.dart';
import 'package:rekindle/screens/epub_reader_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _chapters = 10;

/// A server holding one streamed book, which remembers the progress written to
/// it the way the real one does.
class _BookServer implements HttpClientAdapter {
  Map<String, dynamic> stored = {'currentPage': 0, 'isCompleted': false};
  final List<Map<String, dynamic>> writes = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    if (path.endsWith('/book/manifest')) {
      return _json({
        'title': 'Book',
        'chapters': [
          for (var i = 0; i < _chapters; i++)
            {'title': 'Chapter $i', 'path': 'OPS/c$i.xhtml'},
        ],
      });
    }
    if (path.contains('/book/content/')) {
      final i = RegExp(r'c(\d+)\.xhtml').firstMatch(path)!.group(1);
      final paragraphs =
          List.generate(60, (n) => '<p>Chapter $i, paragraph $n.</p>').join();
      return ResponseBody.fromBytes(
          utf8.encode(
              '<html><body><h1>Chapter $i</h1>$paragraphs</body></html>'),
          200);
    }
    if (path.endsWith('/progress') && options.method == 'POST') {
      final body = Map<String, dynamic>.from(options.data as Map);
      writes.add(body);
      stored = body;
      return _json(stored);
    }
    if (path.endsWith('/progress')) return _json(stored);
    if (path.endsWith('/pagecount')) {
      return _json({'pageCount': _chapters, 'spreads': <bool>[]});
    }
    return _json(<String, dynamic>{});
  }

  ResponseBody _json(Object body) =>
      ResponseBody.fromString(jsonEncode(body), 200, headers: {
        Headers.contentTypeHeader: ['application/json'],
      });

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  late Database db;
  late _BookServer server;
  late Directory downloads;

  setUp(() async {
    downloads = await Directory.systemTemp.createTemp('rekindle-test');
    SharedPreferences.setMockInitialValues(
        {'download_directory': downloads.path});
    await Prefs.init();
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 3,
        singleInstance: false,
        onCreate: LocalDb.onCreate,
      ),
    );
    server = _BookServer();
  });

  tearDown(() async {
    await db.close();
    await downloads.delete(recursive: true);
  });

  /// Lets real I/O (the database, isolates) and fake time both move on.
  Future<void> settle(WidgetTester tester, {int seconds = 1}) async {
    for (var i = 0; i < seconds * 5; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  // The reader used to throw in dispose, before its closing save: progress then
  // depended on a debounce that outlived the reader, which could fire during the
  // next open and save that session's starting place over the newer one.
  testWidgets('reading on after reopening a book is saved', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final client = ApiClient.anonymous(baseUrl: 'http://server.test/');
    client.dio.httpClientAdapter = server;
    final navigator = GlobalKey<NavigatorState>();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        localDbProvider.overrideWithValue(db),
        apiClientProvider.overrideWithValue(client),
        isOnlineProvider.overrideWithValue(true),
      ],
      child: MaterialApp(navigatorKey: navigator, home: const SizedBox()),
    ));

    Future<void> openBook() async {
      navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const EpubReaderScreen(mediaId: 'book', title: 'Book'),
      ));
      await settle(tester, seconds: 3);
    }

    Future<void> closeBook() async {
      navigator.currentState!.pop();
      await settle(tester, seconds: 3);
    }

    String chapterShown() => tester
        .widget<Text>(find.textContaining(RegExp(r'^Chapter \d+ / ')))
        .data!;

    Future<void> nextChapter() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await settle(tester, seconds: 2);
    }

    // First session: read from chapter 1 to chapter 3.
    await openBook();
    expect(chapterShown(), 'Chapter 1 / $_chapters');
    await nextChapter();
    await nextChapter();
    expect(chapterShown(), 'Chapter 3 / $_chapters');
    await settle(tester, seconds: 4);
    await closeBook();
    expect(server.stored['currentPage'], 2, reason: 'writes: ${server.writes}');

    // Second session: reopen at chapter 3, read on to chapter 5, and close
    // straight away, before the debounced save would have run.
    await openBook();
    expect(chapterShown(), 'Chapter 3 / $_chapters');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await settle(tester);
    expect(chapterShown(), 'Chapter 5 / $_chapters');
    await closeBook();
    expect(server.stored['currentPage'], 4, reason: 'writes: ${server.writes}');

    // Third session opens where the second left off, and leaving it alone
    // doesn't move the saved place back.
    await openBook();
    expect(chapterShown(), 'Chapter 5 / $_chapters');
    await settle(tester, seconds: 4);
    await closeBook();
    expect(server.stored['currentPage'], 4, reason: 'writes: ${server.writes}');
  });
}
