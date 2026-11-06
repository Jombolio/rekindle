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
import 'package:rekindle/core/epub/reading_style.dart';
import 'package:rekindle/core/storage/prefs.dart';
import 'package:rekindle/providers/auth_provider.dart';
import 'package:rekindle/providers/connectivity_provider.dart';
import 'package:rekindle/screens/epub_reader_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _chapters = 6;

/// A server holding one streamed book of long chapters, which remembers the
/// progress written to it.
class _BookServer implements HttpClientAdapter {
  Map<String, dynamic> stored = {'currentPage': 0, 'isCompleted': false};

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
          List.generate(80, (n) => '<p>Chapter $i paragraph $n is here.</p>')
              .join();
      return ResponseBody.fromBytes(
          utf8.encode('<html><body>$paragraphs</body></html>'), 200);
    }
    if (path.endsWith('/progress') && options.method == 'POST') {
      stored = Map<String, dynamic>.from(options.data as Map);
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

  late BookLayout layout;

  setUp(() async {
    downloads = await Directory.systemTemp.createTemp('rekindle-test');
    SharedPreferences.setMockInitialValues({
      'download_directory': downloads.path,
      'reading_style': ReadingStyle(layout: layout, animations: false).toJson(),
    });
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

  Future<GlobalKey<NavigatorState>> pumpApp(WidgetTester tester) async {
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
    return navigator;
  }

  Future<void> openBook(
      WidgetTester tester, GlobalKey<NavigatorState> navigator) async {
    navigator.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const EpubReaderScreen(mediaId: 'book', title: 'Book'),
    ));
    await settle(tester, seconds: 3);
  }

  Future<void> closeBook(
      WidgetTester tester, GlobalKey<NavigatorState> navigator) async {
    navigator.currentState!.pop();
    await settle(tester, seconds: 3);
  }

  String position(WidgetTester tester) => tester
      .widget<Text>(find.textContaining(RegExp(r'^Chapter \d+ / ')))
      .data!;

  group('single page', () {
    setUpAll(() => layout = BookLayout.page);
    testWidgets('single pages turn, cross chapters, and reopen where they were',
        (tester) async {
      final navigator = await pumpApp(tester);
      await openBook(tester, navigator);

      final first = position(tester);
      expect(first, startsWith('Chapter 1 / $_chapters · Page 1 of '));
      final pages =
          int.parse(RegExp(r'of (\d+)$').firstMatch(first)!.group(1)!);
      expect(pages, greaterThan(1), reason: 'a long chapter spans pages');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await settle(tester);
      expect(position(tester), 'Chapter 1 / $_chapters · Page 2 of $pages');

      // Past the last page is the next chapter's first.
      for (var i = 2; i <= pages; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await settle(tester);
      }
      expect(
          position(tester), startsWith('Chapter 2 / $_chapters · Page 1 of'));

      // And back from there is the previous chapter's last page.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await settle(tester);
      expect(
          position(tester), 'Chapter 1 / $_chapters · Page $pages of $pages');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await settle(tester);
      final before = position(tester);
      await closeBook(tester, navigator);
      expect(server.stored['currentPage'], 0);

      await openBook(tester, navigator);
      expect(position(tester), before);
      await closeBook(tester, navigator);
    });
  });

  group('two pages', () {
    setUpAll(() => layout = BookLayout.spread);
    testWidgets('two-page spreads show two pages at a time', (tester) async {
      final navigator = await pumpApp(tester);
      await openBook(tester, navigator);

      expect(position(tester),
          startsWith('Chapter 1 / $_chapters · Pages 1–2 of'));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await settle(tester);
      expect(position(tester),
          startsWith('Chapter 1 / $_chapters · Pages 3–4 of'));
      await closeBook(tester, navigator);
    });
  });

  group('continuous', () {
    setUpAll(() => layout = BookLayout.continuous);
    testWidgets('continuous scrolling runs into the next chapter and saves it',
        (tester) async {
      final navigator = await pumpApp(tester);
      await openBook(tester, navigator);
      expect(position(tester), 'Chapter 1 / $_chapters');

      // Scroll well past the first chapter's end.
      for (var i = 0; i < 12; i++) {
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
        await settle(tester);
      }
      final reached = position(tester);
      expect(reached, isNot('Chapter 1 / $_chapters'));
      await settle(tester, seconds: 4);
      await closeBook(tester, navigator);
      final chapter =
          int.parse(RegExp(r'^Chapter (\d+)').firstMatch(reached)!.group(1)!);
      expect(server.stored['currentPage'], chapter - 1);

      await openBook(tester, navigator);
      expect(position(tester), reached);
      await closeBook(tester, navigator);
    });
  });
}
