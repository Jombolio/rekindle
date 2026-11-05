import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rekindle/core/import/book_files.dart';
import 'package:rekindle/core/import/book_import.dart';

import 'fake_import_backend.dart';

ImportBook book(String name,
        [ImportStatus status = ImportStatus.ready, String? reason]) =>
    ImportBook(path: '/books/$name', title: name, status: status, reason: reason);

DioException httpError(int status, [Object? data]) {
  final options = RequestOptions(path: 'x');
  return DioException(
    requestOptions: options,
    response:
        Response(requestOptions: options, statusCode: status, data: data),
  );
}

void main() {
  group('ImportStatus.fromServer', () {
    test('maps every status', () {
      expect(ImportStatus.fromServer('Ready'), ImportStatus.ready);
      expect(ImportStatus.fromServer('AlreadyInLibrary'),
          ImportStatus.alreadyInLibrary);
      expect(ImportStatus.fromServer('DrmProtected'), ImportStatus.drmProtected);
      expect(ImportStatus.fromServer('UnsupportedFormat'),
          ImportStatus.unsupportedFormat);
    });

    test('never treats something it does not recognise as ready', () {
      expect(ImportStatus.fromServer('SomethingNew'), ImportStatus.unreadable);
      expect(ImportStatus.fromServer(null), ImportStatus.unreadable);
    });
  });

  group('inspectBook', () {
    test('sends a Kindle file only its head', () async {
      final backend = FakeImportBackend();
      final files = FakeBookFiles(head: Uint8List.fromList([1, 2, 3]));

      final result =
          await inspectBook('/k/My_Book_B00ABCDEFG.azw3', 'lib', backend, files);

      expect(backend.inspections.single.head, [1, 2, 3]);
      expect(result.status, ImportStatus.ready);
      expect(result.title, 'My Book');
    });

    test('takes the title and author the server read', () async {
      final backend = FakeImportBackend()
        ..inspectResult = (_) => const BookInspection(
            status: ImportStatus.ready, title: 'Real Title', author: 'Writer');

      final result =
          await inspectBook('/k/x.mobi', 'lib', backend, FakeBookFiles());

      expect(result.title, 'Real Title');
      expect(result.author, 'Writer');
    });

    test('reports what the server found', () async {
      final backend = FakeImportBackend()
        ..inspectResult = (_) => const BookInspection(
            status: ImportStatus.drmProtected, reason: drmReason);

      final result =
          await inspectBook('/k/x.azw', 'lib', backend, FakeBookFiles());

      expect(result.status, ImportStatus.drmProtected);
      expect(result.reason, drmReason);
    });

    test('sends no head for KFX', () async {
      final backend = FakeImportBackend();

      await inspectBook('/k/x.kfx', 'lib', backend, FakeBookFiles());

      expect(backend.inspections.single.head, isNull);
    });

    test('sends an EPUB\'s own metadata and no head', () async {
      final backend = FakeImportBackend();
      final files = FakeBookFiles(
          epub: const EpubInfo(title: 'Epub Title', author: 'Epub Author'));

      final result = await inspectBook('/k/x.epub', 'lib', backend, files);

      expect(backend.inspections.single.head, isNull);
      expect(backend.inspections.single.title, 'Epub Title');
      expect(backend.inspections.single.author, 'Epub Author');
      expect(result.title, 'Epub Title');
    });

    test('reports a protected EPUB without asking the server', () async {
      final backend = FakeImportBackend();
      final files =
          FakeBookFiles(epub: const EpubInfo(title: 'T', isProtected: true));

      final result = await inspectBook('/k/x.epub', 'lib', backend, files);

      expect(result.status, ImportStatus.drmProtected);
      expect(result.reason, drmReason);
      expect(backend.inspections, isEmpty);
    });

    test('reports an unreadable EPUB without asking the server', () async {
      final backend = FakeImportBackend();
      final files = FakeBookFiles(epub: const EpubInfo(isReadable: false));

      final result = await inspectBook('/k/x.epub', 'lib', backend, files);

      expect(result.status, ImportStatus.unreadable);
      expect(backend.inspections, isEmpty);
    });

    test('reports a file it cannot read', () async {
      final backend = FakeImportBackend();
      final files =
          FakeBookFiles(headError: const FileSystemException('unplugged'));

      final result = await inspectBook('/k/x.mobi', 'lib', backend, files);

      expect(result.status, ImportStatus.unreadable);
      expect(backend.inspections, isEmpty);
    });

    test('does not call a book ready when the server cannot be asked',
        () async {
      final backend = FakeImportBackend()
        ..inspectError = httpError(500);

      expect(
        inspectBook('/k/x.mobi', 'lib', backend, FakeBookFiles()),
        throwsA(isA<DioException>()),
      );
    });
  });

  group('markDuplicates', () {
    test('keeps the first file of each name', () {
      final result = markDuplicates([
        const ImportBook(path: '/a/x.mobi', title: 'x', status: ImportStatus.ready),
        const ImportBook(path: '/b/X.MOBI', title: 'x', status: ImportStatus.ready),
        const ImportBook(path: '/b/y.mobi', title: 'y', status: ImportStatus.ready),
      ]);

      expect(result.map((b) => b.status), [
        ImportStatus.ready,
        ImportStatus.alreadyInLibrary,
        ImportStatus.ready,
      ]);
      expect(result[1].reason, duplicateReason);
    });

    test('leaves books that are not going to be uploaded as they are', () {
      final result = markDuplicates([
        const ImportBook(
            path: '/a/x.mobi', title: 'x', status: ImportStatus.drmProtected),
        const ImportBook(path: '/b/x.mobi', title: 'x', status: ImportStatus.ready),
      ]);

      expect(result.map((b) => b.status),
          [ImportStatus.drmProtected, ImportStatus.ready]);
    });
  });

  group('runImport', () {
    test('uploads the ready books in order, then scans once', () async {
      final backend = FakeImportBackend();

      final report = await runImport(
        books: [book('a.mobi'), book('b.mobi'), book('c.mobi')],
        libraryId: 'lib',
        backend: backend,
        run: ImportRun(),
      );

      expect(backend.uploads, ['a.mobi', 'b.mobi', 'c.mobi']);
      expect(backend.scans, 1);
      expect(report.withOutcome(ImportOutcome.imported).length, 3);
      expect(report.scanNote, isNull);
    });

    test('uploads one at a time', () async {
      final backend = FakeImportBackend();
      var inFlight = 0;
      var most = 0;
      backend.onUpload = (name) async {
        inFlight++;
        most = most > inFlight ? most : inFlight;
        await Future<void>.delayed(Duration.zero);
        inFlight--;
      };

      await runImport(
        books: [book('a.mobi'), book('b.mobi')],
        libraryId: 'lib',
        backend: backend,
        run: ImportRun(),
      );

      expect(most, 1);
    });

    test('never uploads a book that is not ready', () async {
      final backend = FakeImportBackend();

      final report = await runImport(
        books: [
          book('drm.azw', ImportStatus.drmProtected, drmReason),
          book('kfx.kfx', ImportStatus.unsupportedFormat, 'No KFX'),
          book('dup.mobi', ImportStatus.alreadyInLibrary, 'Have it'),
          book('bad.mobi', ImportStatus.unreadable, 'Damaged'),
          book('ok.mobi'),
        ],
        libraryId: 'lib',
        backend: backend,
        run: ImportRun(),
      );

      expect(backend.uploads, ['ok.mobi']);
      final skipped = report.withOutcome(ImportOutcome.skipped).toList();
      expect(skipped.map((r) => r.reason),
          [drmReason, 'No KFX', 'Have it', 'Damaged']);
    });

    test('does not scan when nothing was uploaded', () async {
      final backend = FakeImportBackend();

      await runImport(
        books: [book('drm.azw', ImportStatus.drmProtected, drmReason)],
        libraryId: 'lib',
        backend: backend,
        run: ImportRun(),
      );

      expect(backend.scans, 0);
    });

    test('carries on past a failure and reports the server\'s reason',
        () async {
      final backend = FakeImportBackend()
        ..uploadErrors['a.mobi'] = httpError(500, {'error': 'Disk full.'});

      final report = await runImport(
        books: [book('a.mobi'), book('b.mobi')],
        libraryId: 'lib',
        backend: backend,
        run: ImportRun(),
      );

      expect(backend.uploads, ['a.mobi', 'b.mobi']);
      final failed = report.withOutcome(ImportOutcome.failed).single;
      expect(failed.book.fileName, 'a.mobi');
      expect(failed.reason, 'Disk full.');
      expect(report.withOutcome(ImportOutcome.imported).single.book.fileName,
          'b.mobi');
      expect(backend.scans, 1);
    });

    test('counts a conflict as skipped, not failed', () async {
      final backend = FakeImportBackend()
        ..uploadErrors['a.mobi'] = httpError(409, {'error': 'exists'});

      final report = await runImport(
        books: [book('a.mobi')],
        libraryId: 'lib',
        backend: backend,
        run: ImportRun(),
      );

      expect(report.withOutcome(ImportOutcome.skipped).single.reason,
          contains('already in this library'));
      expect(report.withOutcome(ImportOutcome.failed), isEmpty);
    });

    test('reports a file that went away, in plain words', () async {
      final backend = FakeImportBackend()
        ..uploadErrors['a.mobi'] = const FileSystemException('gone');

      final report = await runImport(
        books: [book('a.mobi')],
        libraryId: 'lib',
        backend: backend,
        run: ImportRun(),
      );

      expect(report.withOutcome(ImportOutcome.failed).single.reason,
          contains('still connected'));
    });

    test('cancelling stops the uploads and still scans what was uploaded',
        () async {
      final backend = FakeImportBackend();
      final run = ImportRun();
      backend.onUpload = (name) async {
        if (name == 'b.mobi') {
          run.cancel();
          throw DioException(
            requestOptions: RequestOptions(path: 'x'),
            type: DioExceptionType.cancel,
          );
        }
      };

      final report = await runImport(
        books: [book('a.mobi'), book('b.mobi'), book('c.mobi')],
        libraryId: 'lib',
        backend: backend,
        run: run,
      );

      expect(backend.uploads, ['a.mobi', 'b.mobi']);
      expect(report.withOutcome(ImportOutcome.imported).single.book.fileName,
          'a.mobi');
      final skipped = report.withOutcome(ImportOutcome.skipped).toList();
      expect(skipped.map((r) => r.book.fileName), ['b.mobi', 'c.mobi']);
      expect(skipped[0].reason, contains('while this book was uploading'));
      expect(skipped[1].reason, contains('before this book was uploaded'));
      expect(report.withOutcome(ImportOutcome.failed), isEmpty);
      expect(backend.scans, 1);
    });

    test('cancel reaches the upload in flight', () async {
      final backend = FakeImportBackend();
      final run = ImportRun();

      final uploading = Completer<void>();
      backend.onUploadToken = (token) async {
        uploading.complete();
        await token.whenCancel;
        throw DioException(
          requestOptions: RequestOptions(path: 'x'),
          type: DioExceptionType.cancel,
        );
      };

      final done = runImport(
        books: [book('a.mobi')],
        libraryId: 'lib',
        backend: backend,
        run: run,
      );
      await uploading.future;
      run.cancel();

      final report = await done;
      expect(report.withOutcome(ImportOutcome.skipped).length, 1);
    });

    test('waits out a scan already running, since it may miss these books',
        () async {
      final backend = FakeImportBackend()..scanAnswers = [false, false, true];

      final report = await runImport(
        books: [book('a.mobi')],
        libraryId: 'lib',
        backend: backend,
        run: ImportRun(),
        scanRetryDelay: Duration.zero,
      );

      expect(backend.scans, 3);
      expect(report.scanNote, isNull);
    });

    test('says so when the library stays busy', () async {
      final backend = FakeImportBackend()..scanAnswers = [false, false];

      final report = await runImport(
        books: [book('a.mobi')],
        libraryId: 'lib',
        backend: backend,
        run: ImportRun(),
        scanRetryDelay: Duration.zero,
        scanAttempts: 2,
      );

      expect(report.scanNote, contains('busy'));
      expect(report.withOutcome(ImportOutcome.imported).length, 1);
    });

    test('says so when the scan cannot be started', () async {
      final backend = FakeImportBackend()..scanError = httpError(500);

      final report = await runImport(
        books: [book('a.mobi')],
        libraryId: 'lib',
        backend: backend,
        run: ImportRun(),
      );

      expect(report.scanNote, contains("couldn't be started"));
    });

    test('reports progress for each book', () async {
      final backend = FakeImportBackend();
      final seen = <String>[];

      await runImport(
        books: [book('a.mobi'), book('b.mobi')],
        libraryId: 'lib',
        backend: backend,
        run: ImportRun(),
        onProgress: (i, total, b, fraction) =>
            seen.add('$i/$total ${b.fileName} $fraction'),
      );

      expect(seen, containsAllInOrder([
        '0/2 a.mobi 0.0',
        '0/2 a.mobi 1.0',
        '1/2 b.mobi 0.0',
        '1/2 b.mobi 1.0',
      ]));
    });
  });

  test('no message suggests a way around DRM', () {
    for (final message in [drmReason, unreadableReason, duplicateReason]) {
      expect(
        message.toLowerCase(),
        isNot(anyOf(contains('remove'), contains('calibre'), contains('strip'),
            contains('convert'), contains('plugin'))),
      );
    }
  });
}
