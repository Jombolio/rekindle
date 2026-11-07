import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rekindle/core/api/api_client.dart';
import 'package:rekindle/core/download/download_state.dart';
import 'package:rekindle/core/models/media.dart';
import 'package:rekindle/core/storage/prefs.dart';
import 'package:rekindle/providers/auth_provider.dart';
import 'package:rekindle/providers/chapter_provider.dart';
import 'package:rekindle/providers/download_provider.dart';
import 'package:rekindle/providers/settings_provider.dart';
import 'package:rekindle/screens/chapter_index_screen.dart';

class _Server implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
      ResponseBody.fromString(jsonEncode(<Object>[]), 200, headers: {
        Headers.contentTypeHeader: ['application/json'],
      });

  @override
  void close({bool force = false}) {}
}

/// Nothing downloaded, without the local database behind the real one.
class _NoDownloads extends DownloadNotifier {
  @override
  DownloadState build(String mediaId) => const DownloadState.idle();
}

Media _media(String id, String title, {bool folder = false}) => Media.fromJson({
      'id': id,
      'libraryId': 'lib',
      'title': title,
      'filePath': '/x',
      'format': folder ? 'folder' : 'cbz',
      'mediaType': folder ? 'folder' : 'archive',
      'relativePath': folder ? 'Series/$title' : 'Series/$title.cbz',
    });

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
  });

  Future<ProviderContainer> pump(WidgetTester tester) async {
    final client = ApiClient.anonymous(baseUrl: 'http://server.test/');
    client.dio.httpClientAdapter = _Server();
    final container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(client),
      downloadProvider.overrideWith(_NoDownloads.new),
      chapterProvider('f1').overrideWith((ref) async => [
            _media('s1', 'Extras', folder: true),
            _media('c1', 'Chapter 1'),
            _media('c2', 'Chapter 2'),
            _media('c3', 'Finale'),
          ]),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: ChapterIndexScreen(folderId: 'f1', folderTitle: 'Series'),
      ),
    ));
    await tester.pump();
    await tester.pump();
    return container;
  }

  // Lets the covers' and marquees' timers run out once the screen is gone.
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  Finder title(String text) =>
      find.descendant(of: find.byType(ListView), matching: find.text(text));

  testWidgets('typing filters the folder and Escape restores it',
      (tester) async {
    await pump(tester);
    expect(title('Chapter 1'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pump();
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'f');
    expect(title('Finale'), findsOneWidget);
    expect(title('Chapter 1'), findsNothing);
    expect(title('Extras'), findsNothing);

    await tester.enterText(find.byType(TextField), 'chapter 2');
    await tester.pump();
    expect(title('Chapter 2'), findsOneWidget);
    expect(title('Chapter 1'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Series'), findsOneWidget);
    for (final t in ['Extras', 'Chapter 1', 'Chapter 2', 'Finale']) {
      expect(title(t), findsOneWidget);
    }
    await finish(tester);
  });

  testWidgets('clearing the search brings the listing back', (tester) async {
    await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Nothing here matches'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
    expect(title('Finale'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('does nothing when the setting is off', (tester) async {
    final container = await pump(tester);
    await container
        .read(settingsProvider.notifier)
        .setTypeToSearch(enabled: false);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
    expect(title('Chapter 1'), findsOneWidget);
    await finish(tester);
  });
}
