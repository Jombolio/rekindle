import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rekindle/core/api/api_client.dart';
import 'package:rekindle/core/db/local_db.dart';
import 'package:rekindle/core/db/local_db_provider.dart';
import 'package:rekindle/core/storage/prefs.dart';
import 'package:rekindle/providers/auth_provider.dart';
import 'package:rekindle/providers/connectivity_provider.dart';
import 'package:rekindle/providers/reader_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Answers like a server, and records the progress written to it.
class _FakeServer implements HttpClientAdapter {
  final List<Map<String, dynamic>> saved = [];

  /// What /pagecount reports. Servers before this change returned the number of
  /// images in the EPUB, and those are still out there.
  int pageCount = 1;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    Object body = const <String, dynamic>{};
    if (options.path.endsWith('/pagecount')) {
      body = {'pageCount': pageCount, 'spreads': <bool>[]};
    } else if (options.method == 'POST' && options.path.endsWith('/progress')) {
      saved.add(Map<String, dynamic>.from(options.data as Map));
    } else if (options.path.endsWith('/progress')) {
      body = {'currentPage': 0, 'isCompleted': false};
    }
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late _FakeServer server;
  late ProviderContainer container;
  const mediaId = 'book-1';
  const ReaderArgs args = (mediaId, null);

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 3,
        singleInstance: false,
        onCreate: LocalDb.onCreate,
      ),
    );
    server = _FakeServer();
    final client = ApiClient.anonymous(baseUrl: 'http://server.test/');
    client.dio.httpClientAdapter = server;
    container = ProviderContainer(overrides: [
      localDbProvider.overrideWithValue(db),
      apiClientProvider.overrideWithValue(client),
      isOnlineProvider.overrideWithValue(true),
    ]);
  });

  tearDown(() async {
    // Let the reader's closing flush finish while the container is still alive.
    container.invalidate(readerProvider(args));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    container.dispose();
    await db.close();
  });

  /// Opens the book as the EPUB screen does, then waits out the provider's
  /// start-up network calls, which used to overwrite the chapter count.
  Future<ReaderNotifier> open({int chapters = 40, int chapter = 0}) async {
    final notifier = container.read(readerProvider(args).notifier);
    notifier.openBook(chapterCount: chapters, chapter: chapter, fraction: null);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return notifier;
  }

  /// Closes the reader, which flushes pending progress.
  Future<void> close() async {
    container.invalidate(readerProvider(args));
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  Future<Map<String, Object?>> localRow() async => (await db.query(
        'progress_queue',
        where: 'media_id = ?',
        whereArgs: [mediaId],
      ))
          .single;

  test("the server's page count does not replace the chapter count", () async {
    await open();
    expect(container.read(readerProvider(args)).totalPages, 40);
  });

  test('turning a chapter saves it, and does not finish the book', () async {
    // The bug: with the count overwritten by a cover's single image, chapter 5
    // clamped to page 0, which is also the last page, so it saved as completed.
    final notifier = await open();

    notifier.setBookPosition(mediaId, chapter: 5, fraction: 0, completed: false);
    await close();

    final row = await localRow();
    expect(row['current_page'], 5);
    expect(row['is_completed'], 0);
    expect(server.saved.first['currentPage'], 5);
    expect(server.saved.first['isCompleted'], false);
  });

  test('the position within a chapter is saved locally and to the server',
      () async {
    final notifier = await open();

    notifier.setBookPosition(mediaId, chapter: 2, fraction: 0.4, completed: false);
    await close();

    expect((await localRow())['position_fraction'], 0.4);
    expect(server.saved.first['positionFraction'], 0.4);
  });

  test('completion comes from the reader, not from reaching the last chapter',
      () async {
    final notifier = await open(chapters: 3);

    notifier.setBookPosition(mediaId, chapter: 2, fraction: 0.1, completed: false);
    await close();
    expect((await localRow())['is_completed'], 0);
  });

  test('the book is completed when the reader says so', () async {
    final notifier = await open(chapters: 3);

    notifier.setBookPosition(mediaId, chapter: 2, fraction: 0.99, completed: true);
    await close();
    expect((await localRow())['is_completed'], 1);
  });

  test('opening and closing a book does not change its saved chapter', () async {
    await open(chapter: 7);
    await close();

    for (final write in server.saved) {
      expect(write['currentPage'], 7);
      expect(write['isCompleted'], false);
    }
  });

  test('closing the comic reader saves the page, not page 0', () async {
    // Closing rebuilt the provider mid-dispose, which threw and reset the state,
    // so every close wrote page 0 over the real progress.
    server.pageCount = 50;
    final notifier = container.read(readerProvider(args).notifier);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    notifier.goToPage(5, mediaId);
    await close();

    expect((await localRow())['current_page'], 5);
    expect(server.saved.last['currentPage'], 5);
  });

  test('the upgrade adds the column and keeps existing progress', () async {
    final old = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await old.execute(
      'CREATE TABLE progress_queue (media_id TEXT PRIMARY KEY, '
      'current_page INTEGER NOT NULL DEFAULT 0, '
      'is_completed INTEGER NOT NULL DEFAULT 0, '
      'last_read_at INTEGER NOT NULL, synced INTEGER NOT NULL DEFAULT 0)',
    );
    await old.insert('progress_queue',
        {'media_id': 'x', 'current_page': 9, 'last_read_at': 1, 'synced': 1});

    await LocalDb.onUpgrade(old, 2, 3);

    final row = (await old.query('progress_queue')).single;
    expect(row['current_page'], 9);
    expect(row['position_fraction'], isNull);
    await old.close();
  });
}
