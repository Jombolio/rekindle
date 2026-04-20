import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Opens (and migrates) the local SQLite database.
/// Call [LocalDb.open] once at startup; reuse the returned [Database].
class LocalDb {
  LocalDb._();

  static Future<Database> open() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dir = await getApplicationDocumentsDirectory();
    final dbDir = Directory('${dir.path}/rekindle');
    await dbDir.create(recursive: true);

    return openDatabase(
      '${dbDir.path}/local.db',
      version: 1,
      onCreate: _onCreate,
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE media_cache (
        id TEXT PRIMARY KEY,
        library_id TEXT NOT NULL,
        title TEXT NOT NULL,
        series TEXT,
        volume INTEGER,
        format TEXT NOT NULL,
        page_count INTEGER,
        downloaded_path TEXT,
        cached_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE progress_queue (
        media_id TEXT PRIMARY KEY,
        current_page INTEGER NOT NULL DEFAULT 0,
        is_completed INTEGER NOT NULL DEFAULT 0,
        last_read_at INTEGER NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE downloads (
        media_id TEXT PRIMARY KEY,
        status TEXT NOT NULL DEFAULT 'idle',
        progress REAL NOT NULL DEFAULT 0,
        local_path TEXT,
        format TEXT NOT NULL,
        title TEXT NOT NULL
      )
    ''');
  }
}
