import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:rekindle/core/import/book_files.dart';
import 'package:rekindle/core/import/book_import.dart';
import 'package:rekindle/core/models/library.dart';

class RecordedInspection {
  final String libraryId;
  final String fileName;
  final Uint8List? head;
  final String? title;
  final String? author;

  const RecordedInspection(
      this.libraryId, this.fileName, this.head, this.title, this.author);
}

class FakeImportBackend implements BookImportBackend {
  List<Library> libraries = const [
    Library(id: 'comics', name: 'Comics', rootPath: '/c', type: 'comic'),
    Library(id: 'books', name: 'Books', rootPath: '/b', type: 'book'),
  ];

  final inspections = <RecordedInspection>[];
  BookInspection Function(String fileName)? inspectResult;
  Object? inspectError;

  final uploads = <String>[];
  final uploadErrors = <String, Object>{};
  Future<void> Function(String fileName)? onUpload;
  Future<void> Function(CancelToken token)? onUploadToken;

  int scans = 0;
  List<bool> scanAnswers = const [];
  Object? scanError;

  @override
  Future<List<Library>> getLibraries() async => libraries;

  @override
  Future<BookInspection> inspect({
    required String libraryId,
    required String fileName,
    Uint8List? head,
    String? title,
    String? author,
  }) async {
    if (inspectError != null) throw inspectError!;
    inspections
        .add(RecordedInspection(libraryId, fileName, head, title, author));
    return inspectResult?.call(fileName) ??
        const BookInspection(status: ImportStatus.ready);
  }

  @override
  Future<void> upload({
    required String libraryId,
    required String path,
    required String fileName,
    required CancelToken cancelToken,
    void Function(int sent, int total)? onProgress,
  }) async {
    uploads.add(fileName);
    await onUpload?.call(fileName);
    await onUploadToken?.call(cancelToken);
    if (uploadErrors[fileName] case final error?) throw error;
    onProgress?.call(10, 10);
  }

  @override
  Future<bool> scan(String libraryId) async {
    final attempt = scans++;
    if (scanError != null) throw scanError!;
    return attempt < scanAnswers.length ? scanAnswers[attempt] : true;
  }
}

class FakeBookFiles extends BookFiles {
  final List<String> books;
  final List<String> kindles;
  final Uint8List? head;
  final Object? headError;
  final EpubInfo epub;

  FakeBookFiles({
    this.books = const [],
    this.kindles = const [],
    this.head,
    this.headError,
    this.epub = const EpubInfo(),
  });

  @override
  Future<List<String>> findBooks(String root) async => books;

  @override
  Future<List<String>> findKindles({List<String>? mountPoints}) async => kindles;

  @override
  Future<Uint8List> readHead(String path) async {
    if (headError != null) throw headError!;
    return head ?? Uint8List(0);
  }

  @override
  Future<EpubInfo> readEpubInfo(String path) async => epub;
}
