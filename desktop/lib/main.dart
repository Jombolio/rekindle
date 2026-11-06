import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/db/local_db_provider.dart';
import 'core/epub/book_font.dart';
import 'core/storage/prefs.dart';
import 'core/update/app_updater.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicences();
  await Prefs.init();
  await initLocalDb();

  // Old files an in-app update couldn't remove while they were running.
  if (kReleaseMode) {
    AppUpdater.cleanupLeftovers(File(Platform.resolvedExecutable).parent.path);
  }

  // Raise the image cache ceiling for desktop — comic pages are large and the
  // default 100 MB fills up fast, causing already-decoded pages to be evicted.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 512 * 1024 * 1024;

  runApp(
    const ProviderScope(
      child: RekindleApp(),
    ),
  );
}
