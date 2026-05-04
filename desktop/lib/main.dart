import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/db/local_db_provider.dart';
import 'core/storage/prefs.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Prefs.init();
  await initLocalDb();

  // Raise the image cache ceiling for desktop — comic pages are large and the
  // default 100 MB fills up fast, causing already-decoded pages to be evicted.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 512 * 1024 * 1024;

  runApp(
    const ProviderScope(
      child: RekindleApp(),
    ),
  );
}
