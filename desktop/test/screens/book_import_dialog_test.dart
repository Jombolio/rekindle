import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rekindle/core/import/book_import.dart';
import 'package:rekindle/screens/book_import_dialog.dart';

import '../core/import/fake_import_backend.dart';

void main() {
  late FakeImportBackend backend;
  late BookImportController controller;

  Future<void> show(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BookImportDialog(backend: backend, controller: controller),
      ),
    ));
    await tester.pumpAndSettle();
  }

  void useFiles(FakeBookFiles files) {
    controller = BookImportController(
        backend: backend, files: files, scanRetryDelay: Duration.zero);
    addTearDown(controller.dispose);
  }

  BookInspection statuses(String fileName) => switch (fileName) {
        'locked.azw' => const BookInspection(
            status: ImportStatus.drmProtected,
            title: 'Locked',
            reason: drmReason),
        'new.kfx' => const BookInspection(
            status: ImportStatus.unsupportedFormat,
            reason: "This book is in KFX format, which Rekindle can't read, so it can't be imported."),
        'have.mobi' => const BookInspection(
            status: ImportStatus.alreadyInLibrary,
            title: 'Have It',
            reason: 'A book with this title is already in this library.'),
        _ => const BookInspection(
            status: ImportStatus.ready, title: 'Good Book', author: 'A Writer'),
      };

  setUp(() {
    backend = FakeImportBackend()..inspectResult = statuses;
  });

  testWidgets('offers a connected Kindle and picks a book library', (tester) async {
    useFiles(FakeBookFiles(kindles: ['E:\\documents']));
    await show(tester);

    expect(find.text('Kindle found'), findsOneWidget);
    expect(find.text('E:\\documents'), findsOneWidget);
    expect(controller.library?.id, 'books');
  });

  testWidgets('says so when no Kindle is connected', (tester) async {
    useFiles(FakeBookFiles());
    await show(tester);

    expect(find.textContaining('No Kindle found'), findsOneWidget);
  });

  testWidgets('previews each book with its status and target library',
      (tester) async {
    useFiles(FakeBookFiles(
      kindles: ['E:\\documents'],
      books: ['/k/good.mobi', '/k/locked.azw', '/k/new.kfx', '/k/have.mobi'],
    ));
    await show(tester);

    await tester.tap(find.text('Use this Kindle'));
    await tester.pumpAndSettle();

    expect(find.text('Good Book'), findsOneWidget);
    expect(find.textContaining('A Writer'), findsOneWidget);
    expect(find.textContaining('to Books'), findsNWidgets(4));
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('DRM-protected'), findsOneWidget);
    expect(find.text('Unsupported format'), findsOneWidget);
    expect(find.text('Already in library'), findsOneWidget);
    expect(find.text('Import 1 book'), findsOneWidget);
    // Nothing moves until the user confirms.
    expect(backend.uploads, isEmpty);
  });

  testWidgets('imports only what is ready, and reports every book',
      (tester) async {
    useFiles(FakeBookFiles(
      kindles: ['E:\\documents'],
      books: ['/k/good.mobi', '/k/locked.azw', '/k/new.kfx'],
    ));
    await show(tester);
    await tester.tap(find.text('Use this Kindle'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Import 1 book'));
    await tester.pumpAndSettle();

    expect(backend.uploads, ['good.mobi']);
    expect(backend.scans, 1);
    expect(find.text('1 imported, 2 skipped, 0 failed.'), findsOneWidget);
    expect(find.text('Imported'), findsOneWidget);
    expect(find.text('Skipped'), findsOneWidget);
    expect(find.text(drmReason), findsOneWidget);
    expect(find.textContaining('KFX format'), findsOneWidget);
  });

  testWidgets('offers nothing to import when no book is ready', (tester) async {
    useFiles(FakeBookFiles(
      kindles: ['E:\\documents'],
      books: ['/k/locked.azw'],
    ));
    await show(tester);
    await tester.tap(find.text('Use this Kindle'));
    await tester.pumpAndSettle();

    final button = tester.widget<ButtonStyleButton>(find.ancestor(
        of: find.text('Import 0 books'),
        matching: find.bySubtype<ButtonStyleButton>()));
    expect(button.onPressed, isNull);
  });

  testWidgets('shows progress and can be cancelled', (tester) async {
    final uploading = Completer<void>();
    backend.onUploadToken = (token) async {
      if (!uploading.isCompleted) uploading.complete();
      await token.whenCancel;
      throw DioException(
        requestOptions: RequestOptions(path: 'x'),
        type: DioExceptionType.cancel,
      );
    };
    useFiles(FakeBookFiles(
      kindles: ['E:\\documents'],
      books: ['/k/one.mobi', '/k/two.mobi'],
    ));
    await show(tester);
    await tester.tap(find.text('Use this Kindle'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Import 2 books'));
    await tester.pump();

    expect(find.text('Uploading 1 of 2'), findsOneWidget);
    expect(find.text('Good Book'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(backend.uploads, ['one.mobi']);
    expect(find.text('0 imported, 2 skipped, 0 failed.'), findsOneWidget);
    expect(find.textContaining('cancelled'), findsNWidgets(2));
  });

  testWidgets('offers another try when the books cannot be checked',
      (tester) async {
    backend.inspectError = DioException(
      requestOptions: RequestOptions(path: 'x'),
      type: DioExceptionType.connectionError,
    );
    useFiles(FakeBookFiles(
      kindles: ['E:\\documents'],
      books: ['/k/good.mobi'],
    ));
    await show(tester);
    await tester.tap(find.text('Use this Kindle'));
    await tester.pumpAndSettle();

    expect(find.textContaining("couldn't be checked"), findsOneWidget);
    expect(find.textContaining('Import'), findsOneWidget); // Only the title.

    backend.inspectError = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text('Import 1 book'), findsOneWidget);
  });

  testWidgets('checks the books again when the library changes', (tester) async {
    useFiles(FakeBookFiles(
      kindles: ['E:\\documents'],
      books: ['/k/good.mobi'],
    ));
    await show(tester);
    await tester.tap(find.text('Use this Kindle'));
    await tester.pumpAndSettle();
    expect(backend.inspections.single.libraryId, 'books');

    await controller.changeLibrary(backend.libraries.first);
    await tester.pumpAndSettle();

    expect(backend.inspections.last.libraryId, 'comics');
    expect(find.textContaining('to Comics'), findsOneWidget);
  });

  testWidgets('cannot be closed during an import', (tester) async {
    final finish = Completer<void>();
    backend.onUpload = (_) => finish.future;
    useFiles(FakeBookFiles(
      kindles: ['E:\\documents'],
      books: ['/k/good.mobi'],
    ));
    await show(tester);
    await tester.tap(find.text('Use this Kindle'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Import 1 book'));
    await tester.pump();

    final close = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.close));
    expect(close.onPressed, isNull);

    finish.complete();
    await tester.pumpAndSettle();

    final closed = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.close));
    expect(closed.onPressed, isNotNull);
  });
}
