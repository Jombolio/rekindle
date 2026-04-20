import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import 'local_db.dart';

/// Provides the open [Database] instance throughout the app.
/// Initialized in [main] before runApp via [initLocalDb].
late Database localDb;

Future<void> initLocalDb() async {
  localDb = await LocalDb.open();
}

final localDbProvider = Provider<Database>((ref) => localDb);
