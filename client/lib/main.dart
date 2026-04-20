import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/db/local_db_provider.dart';
import 'core/storage/prefs.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Prefs.init();
  await initLocalDb();

  runApp(
    const ProviderScope(
      child: RekindleApp(),
    ),
  );
}
