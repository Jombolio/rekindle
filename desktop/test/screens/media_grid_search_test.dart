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
import 'package:rekindle/providers/download_provider.dart';
import 'package:rekindle/providers/media_provider.dart';
import 'package:rekindle/screens/media_grid_screen.dart';

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

Media _folder(String id, String title) => Media.fromJson({
      'id': id,
      'libraryId': 'lib',
      'title': title,
      'filePath': '/x',
      'format': 'folder',
      'mediaType': 'folder',
      'relativePath': title,
    });

final _folders = [_folder('a', 'Batman'), _folder('b', 'Naruto')];

/// The library's first page, without the network.
class _Listing extends MediaListNotifier {
  @override
  Future<List<Media>> build(String libraryId) async => _folders;

  @override
  Future<void> refreshIfStale(String libraryId) async {}
}

class _NoDownloads extends DownloadNotifier {
  @override
  DownloadState build(String mediaId) => const DownloadState.idle();
}

class _NoFolderDownloads extends FolderDownloadNotifier {
  @override
  FolderDownloadState build(String folderId) =>
      const FolderDownloadState.idle();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
  });

  testWidgets('typing opens the library search holding the typed text',
      (tester) async {
    final queries = <String>[];
    final client = ApiClient.anonymous(baseUrl: 'http://server.test/');
    client.dio.httpClientAdapter = _Server();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(client),
        downloadProvider.overrideWith(_NoDownloads.new),
        folderDownloadProvider.overrideWith(_NoFolderDownloads.new),
        mediaListProvider.overrideWith(_Listing.new),
        folderSearchProvider.overrideWith((ref, args) async {
          queries.add(args.query);
          return [
            for (final f in _folders)
              if (f.title.toLowerCase().contains(args.query.toLowerCase())) f
          ];
        }),
      ],
      child: const MaterialApp(
        home: MediaGridScreen(libraryId: 'lib', libraryName: 'Comics'),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('Comics'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'r');
    expect(field.focusNode!.hasFocus, isTrue);

    // The search waits for typing to pause before it asks the server.
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(queries, ['r']);
    expect(find.widgetWithText(ListTile, 'Naruto'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Batman'), findsNothing);

    // Escape closes the search and brings the grid back.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Comics'), findsOneWidget);
    expect(find.text('Batman'), findsOneWidget);

    // Emptying a typed search does the same.
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.pump();
    await tester.pump();
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Naruto'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
