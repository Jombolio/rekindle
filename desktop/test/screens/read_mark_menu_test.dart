import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rekindle/core/api/api_client.dart';
import 'package:rekindle/core/models/media.dart';
import 'package:rekindle/core/models/progress_summary.dart';
import 'package:rekindle/providers/auth_provider.dart';
import 'package:rekindle/screens/widgets/read_mark_menu.dart';

class _Server implements HttpClientAdapter {
  final List<String> calls = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    calls.add('${options.method} ${options.path}');
    return ResponseBody.fromString(jsonEncode({'markedRead': true}), 200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  Media media({bool folder = false}) => Media.fromJson({
        'id': 'm1',
        'libraryId': 'lib',
        'title': 'Chapter 1',
        'filePath': '/x',
        'format': folder ? 'folder' : 'cbz',
        'mediaType': folder ? 'folder' : 'archive',
      });

  Future<_Server> pump(WidgetTester tester,
      {required Media item, ProgressSummary? summary}) async {
    final server = _Server();
    final client = ApiClient.anonymous(baseUrl: 'http://server.test/');
    client.dio.httpClientAdapter = server;
    await tester.pumpWidget(ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(client)],
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: ReadMarkMenuArea(
              media: item,
              summary: summary,
              child: const SizedBox(width: 200, height: 60, child: Text('row')),
            ),
          ),
        ),
      ),
    ));
    return server;
  }

  Future<void> rightClick(WidgetTester tester) async {
    await tester.tap(find.text('row'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
  }

  testWidgets('right-click marks a chapter as read', (tester) async {
    final server = await pump(tester, item: media());
    await rightClick(tester);
    expect(find.text('Remove read mark'), findsNothing);

    await tester.tap(find.text('Mark as read'));
    await tester.pumpAndSettle();
    expect(server.calls, ['PUT api/media/m1/read-mark']);
    expect(find.text('Marked as read.'), findsOneWidget);
  });

  testWidgets('a marked chapter offers to remove the mark', (tester) async {
    final server = await pump(tester,
        item: media(),
        summary: const ProgressSummary(
            mediaId: 'm1', progress: 1, isCompleted: true, markedRead: true));
    await rightClick(tester);
    expect(find.text('Mark as read'), findsNothing);

    await tester.tap(find.text('Remove read mark'));
    await tester.pumpAndSettle();
    expect(server.calls, ['DELETE api/media/m1/read-mark']);
  });

  testWidgets('an annual can be left out of series tracking', (tester) async {
    final server = await pump(tester, item: media());
    await rightClick(tester);
    expect(find.text('Track archive again'), findsNothing);

    await tester.tap(find.text('Ignore archive tracking'));
    await tester.pumpAndSettle();
    expect(server.calls, ['PUT api/media/m1/tracking-ignore']);
    expect(find.text("Left out of the series' progress."), findsOneWidget);
  });

  testWidgets('an ignored archive can be tracked again', (tester) async {
    final server = await pump(tester,
        item: media(),
        summary: const ProgressSummary(
            mediaId: 'm1', progress: 0.2, isCompleted: false, ignored: true));
    await rightClick(tester);
    expect(find.text('Ignore archive tracking'), findsNothing);

    await tester.tap(find.text('Track archive again'));
    await tester.pumpAndSettle();
    expect(server.calls, ['DELETE api/media/m1/tracking-ignore']);
  });

  testWidgets('a series offers both, for every chapter in it', (tester) async {
    await pump(tester, item: media(folder: true));
    await rightClick(tester);
    expect(find.text('Mark series as read'), findsOneWidget);
    expect(find.text('Remove read marks'), findsOneWidget);
  });
}
