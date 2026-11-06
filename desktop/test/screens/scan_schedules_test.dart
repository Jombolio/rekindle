import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rekindle/core/api/admin_api.dart';
import 'package:rekindle/core/api/api_client.dart';
import 'package:rekindle/screens/widgets/scan_schedules.dart';

/// A server with two libraries, one scanned daily, which records changes.
class _Server implements HttpClientAdapter {
  final bool old;
  final Map<String, int> intervals = {'a': 24, 'b': 0};
  final List<Map<String, dynamic>> puts = [];

  _Server({this.old = false});

  Map<String, dynamic> _row(String id) => {
        'libraryId': id,
        'libraryName': id == 'a' ? 'Comics' : 'Books',
        'intervalHours': intervals[id],
        'lastRunAt': null,
        'nextRunAt': intervals[id] == 0 ? null : '2026-11-07T06:00:00Z',
      };

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    if (old) return ResponseBody.fromString('', 404);
    if (options.method == 'PUT') {
      final id = options.path.split('/').last;
      final body = Map<String, dynamic>.from(options.data as Map);
      puts.add({'id': id, ...body});
      intervals[id] = body['intervalHours'] as int;
      return _json(_row(id));
    }
    return _json([_row('a'), _row('b')]);
  }

  ResponseBody _json(Object body) =>
      ResponseBody.fromString(jsonEncode(body), 200, headers: {
        Headers.contentTypeHeader: ['application/json'],
      });

  @override
  void close({bool force = false}) {}
}

void main() {
  Future<_Server> pump(WidgetTester tester, {bool old = false}) async {
    final server = _Server(old: old);
    final client = ApiClient.anonymous(baseUrl: 'http://server.test/');
    client.dio.httpClientAdapter = server;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ScanSchedulesTab(api: AdminApi(client))),
    ));
    await tester.pumpAndSettle();
    return server;
  }

  testWidgets('lists each library with its schedule', (tester) async {
    await pump(tester);
    expect(find.text('Comics'), findsOneWidget);
    expect(find.text('Daily'), findsOneWidget);
    expect(find.textContaining('Next: '), findsOneWidget);
    expect(find.text('Books'), findsOneWidget);
    expect(find.text('Only scanned when someone presses Scan'), findsOneWidget);
  });

  testWidgets('choosing an interval saves it', (tester) async {
    final server = await pump(tester);
    await tester.tap(find.text('Off'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Every 6 hours').last);
    await tester.pumpAndSettle();

    expect(server.puts, [
      {'id': 'b', 'intervalHours': 6}
    ]);
    expect(find.text('Every 6 hours'), findsOneWidget);
  });

  testWidgets('an older server says it needs updating', (tester) async {
    await pump(tester, old: true);
    expect(find.text('Your server needs updating to schedule scans.'),
        findsOneWidget);
  });

  test('times read as today, tomorrow, or a date', () {
    final now = DateTime(2026, 11, 6, 9);
    expect(scanTimeLabel(DateTime(2026, 11, 6, 18), now: now), 'Today 18:00');
    expect(
        scanTimeLabel(DateTime(2026, 11, 7, 6, 5), now: now), 'Tomorrow 06:05');
    expect(scanTimeLabel(DateTime(2026, 11, 13, 9, 30), now: now),
        'Fri 13 Nov 09:30');
  });
}
