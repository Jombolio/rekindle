import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/library.dart';
import 'book_files.dart';

/// Protected and KFX books are only ever reported. These messages say why a book
/// can't be imported and stop there.
const drmReason = "This book is protected by DRM, so it can't be imported.";
const unreadableReason = "This file couldn't be read as a book. It may be damaged.";
const duplicateReason = 'Another copy of this file is also in this import.';

enum ImportStatus {
  ready('Ready'),
  alreadyInLibrary('Already in library'),
  drmProtected('DRM-protected'),
  unsupportedFormat('Unsupported format'),
  unreadable("Can't be read");

  final String label;
  const ImportStatus(this.label);

  /// Anything this version doesn't recognise isn't uploaded.
  static ImportStatus fromServer(String? name) => switch (name) {
        'Ready' => ready,
        'AlreadyInLibrary' => alreadyInLibrary,
        'DrmProtected' => drmProtected,
        'UnsupportedFormat' => unsupportedFormat,
        _ => unreadable,
      };
}

class BookInspection {
  final ImportStatus status;
  final String? title;
  final String? author;
  final String? reason;

  const BookInspection({
    required this.status,
    this.title,
    this.author,
    this.reason,
  });
}

class ImportBook {
  final String path;
  final String title;
  final String? author;
  final ImportStatus status;
  final String? reason;

  const ImportBook({
    required this.path,
    required this.title,
    this.author,
    required this.status,
    this.reason,
  });

  String get fileName => p.basename(path);
}

enum ImportOutcome { imported, skipped, failed }

class ImportResult {
  final ImportBook book;
  final ImportOutcome outcome;
  final String? reason;

  const ImportResult(this.book, this.outcome, [this.reason]);
}

class ImportReport {
  final List<ImportResult> results;

  /// Set when the books are on the server but aren't in the library yet.
  final String? scanNote;

  const ImportReport(this.results, {this.scanNote});

  Iterable<ImportResult> withOutcome(ImportOutcome outcome) =>
      results.where((r) => r.outcome == outcome);
}

/// The server calls an import makes.
abstract class BookImportBackend {
  Future<List<Library>> getLibraries();

  Future<BookInspection> inspect({
    required String libraryId,
    required String fileName,
    Uint8List? head,
    String? title,
    String? author,
  });

  /// Adds the file without scanning. Throws a [DioException] when it isn't added.
  Future<void> upload({
    required String libraryId,
    required String path,
    required String fileName,
    required CancelToken cancelToken,
    void Function(int sent, int total)? onProgress,
  });

  /// Returns false when a scan was already running, so none was started.
  Future<bool> scan(String libraryId);
}

/// Checks one book: DRM and metadata for an EPUB here, since its directory is at
/// the end of the file, and everything else by the server from the file's head.
Future<ImportBook> inspectBook(
  String path,
  String libraryId,
  BookImportBackend backend,
  BookFiles files,
) async {
  final fileName = p.basename(path);
  final fallbackTitle = titleFromFileName(fileName);
  ImportBook unreadable() => ImportBook(
        path: path,
        title: fallbackTitle,
        status: ImportStatus.unreadable,
        reason: unreadableReason,
      );

  final extension = BookFiles.extensionOf(path);
  Uint8List? head;
  String? title;
  String? author;
  if (extension == 'epub') {
    final info = await files.readEpubInfo(path);
    if (!info.isReadable) return unreadable();
    if (info.isProtected) {
      return ImportBook(
        path: path,
        title: info.title ?? fallbackTitle,
        author: info.author,
        status: ImportStatus.drmProtected,
        reason: drmReason,
      );
    }
    title = info.title;
    author = info.author;
  } else if (extension != 'kfx') {
    try {
      head = await files.readHead(path);
    } on FileSystemException {
      return unreadable();
    }
  }

  final result = await backend.inspect(
    libraryId: libraryId,
    fileName: fileName,
    head: head,
    title: title,
    author: author,
  );
  return ImportBook(
    path: path,
    title: result.title ?? title ?? fallbackTitle,
    author: result.author ?? author,
    status: result.status,
    reason: result.reason ??
        (result.status == ImportStatus.ready ? null : unreadableReason),
  );
}

/// Uploads go to one folder, where a second file of the same name can't land.
List<ImportBook> markDuplicates(List<ImportBook> books) {
  final seen = <String>{};
  return [
    for (final book in books)
      if (book.status == ImportStatus.ready &&
          !seen.add(book.fileName.toLowerCase()))
        ImportBook(
          path: book.path,
          title: book.title,
          author: book.author,
          status: ImportStatus.alreadyInLibrary,
          reason: duplicateReason,
        )
      else
        book,
  ];
}

/// Tells the import how far along it is, and lets it be cancelled.
class ImportRun {
  final _cancelToken = CancelToken();
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
    _cancelToken.cancel();
  }
}

/// Uploads the ready books one at a time, then asks for one scan of the library.
/// A cancel stops the uploads and not the scan, which the books already uploaded
/// still need.
Future<ImportReport> runImport({
  required List<ImportBook> books,
  required String libraryId,
  required BookImportBackend backend,
  required ImportRun run,
  void Function(int index, int total, ImportBook book, double fraction)?
      onProgress,
  void Function()? onScanning,
  Duration scanRetryDelay = const Duration(seconds: 3),
  int scanAttempts = 40,
}) async {
  final results = <ImportResult>[];
  final ready = books.where((b) => b.status == ImportStatus.ready).toList();
  var needsScan = false;

  for (var i = 0; i < ready.length; i++) {
    final book = ready[i];
    if (run.isCancelled) {
      results.add(ImportResult(book, ImportOutcome.skipped,
          'The import was cancelled before this book was uploaded.'));
      continue;
    }
    onProgress?.call(i, ready.length, book, 0);
    try {
      await backend.upload(
        libraryId: libraryId,
        path: book.path,
        fileName: book.fileName,
        cancelToken: run._cancelToken,
        onProgress: (sent, total) {
          if (total > 0) onProgress?.call(i, ready.length, book, sent / total);
        },
      );
      results.add(ImportResult(book, ImportOutcome.imported));
      needsScan = true;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        // The server may have finished receiving it just as this was cancelled.
        needsScan = true;
        results.add(ImportResult(book, ImportOutcome.skipped,
            'The import was cancelled while this book was uploading.'));
      } else if (e.response?.statusCode == 409) {
        results.add(ImportResult(book, ImportOutcome.skipped,
            'A file with this name is already in this library.'));
      } else {
        results.add(ImportResult(book, ImportOutcome.failed, uploadError(e)));
      }
    } on FileSystemException {
      results.add(ImportResult(book, ImportOutcome.failed,
          "The file couldn't be read. If it's on a device, check that it's still connected."));
    }
  }

  for (final book in books.where((b) => b.status != ImportStatus.ready)) {
    results.add(ImportResult(book, ImportOutcome.skipped, book.reason));
  }

  String? scanNote;
  if (needsScan) {
    onScanning?.call();
    scanNote = await _scanOnce(libraryId, backend, scanRetryDelay, scanAttempts);
  }
  return ImportReport(results, scanNote: scanNote);
}

/// A scan that was already running may have missed these books, so this waits
/// for it to finish and starts another rather than settling for it.
Future<String?> _scanOnce(
  String libraryId,
  BookImportBackend backend,
  Duration retryDelay,
  int attempts,
) async {
  try {
    for (var attempt = 0; attempt < attempts; attempt++) {
      if (attempt > 0) await Future<void>.delayed(retryDelay);
      if (await backend.scan(libraryId)) return null;
    }
    return "The library is busy with another scan, so these books may not appear until it's scanned again.";
  } on DioException {
    return "The library scan couldn't be started, so these books won't appear until it's scanned again.";
  }
}

String uploadError(DioException e) {
  final data = e.response?.data;
  if (data is Map && data['error'] is String) return data['error'] as String;
  return switch (e.type) {
    DioExceptionType.connectionError ||
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout =>
      "The server couldn't be reached.",
    _ when e.response?.statusCode == 403 =>
      "This account isn't allowed to add books.",
    _ when e.response?.statusCode == 413 => 'This file is too large to upload.',
    _ => 'The server reported an error.',
  };
}

enum ImportStep { source, inspecting, preview, importing, report }

/// Drives the import dialog through source, preview, import and report.
class BookImportController extends ChangeNotifier {
  final BookImportBackend backend;
  final BookFiles files;
  final Duration scanRetryDelay;

  BookImportController({
    required this.backend,
    this.files = const BookFiles(),
    this.scanRetryDelay = const Duration(seconds: 3),
  });

  ImportStep step = ImportStep.source;
  List<Library> libraries = const [];
  Library? library;
  List<String> kindles = const [];
  bool detecting = false;
  String? root;
  List<String> _paths = const [];
  List<ImportBook> books = const [];
  int inspected = 0;
  String? error;

  int current = 0;
  int total = 0;
  ImportBook? currentBook;
  double currentFraction = 0;
  bool scanning = false;
  ImportRun? _run;
  ImportReport? report;

  // Each preview's generation, so a stale one stops when the library changes or
  // the user goes back.
  int _inspection = 0;
  bool _disposed = false;

  int get readyCount =>
      books.where((b) => b.status == ImportStatus.ready).length;

  bool get cancelling => _run?.isCancelled ?? false;

  Future<void> load() async {
    await Future.wait([_loadLibraries(), detectKindles()]);
  }

  Future<void> _loadLibraries() async {
    try {
      libraries = await backend.getLibraries();
      // Other library types can hold books, but this is what's usually wanted.
      library = libraries.where((l) => l.type == 'book').firstOrNull ??
          libraries.firstOrNull;
    } on DioException catch (e) {
      error = uploadError(e);
    }
    _notify();
  }

  Future<void> detectKindles() async {
    detecting = true;
    _notify();
    kindles = await files.findKindles();
    detecting = false;
    _notify();
  }

  Future<void> chooseSource(String path) async {
    root = path;
    error = null;
    step = ImportStep.inspecting;
    books = const [];
    inspected = 0;
    _notify();

    final generation = ++_inspection;
    _paths = await files.findBooks(path);
    if (generation != _inspection) return;
    await _inspect(generation);
  }

  Future<void> changeLibrary(Library? value) async {
    if (value == null || value.id == library?.id) return;
    library = value;
    // What's "already in library" depends on which library it is.
    if (step == ImportStep.source) {
      _notify();
      return;
    }
    error = null;
    step = ImportStep.inspecting;
    books = const [];
    inspected = 0;
    _notify();
    await _inspect(++_inspection);
  }

  /// Runs the preview again after it couldn't reach the server.
  Future<void> retryInspection() async {
    error = null;
    step = ImportStep.inspecting;
    books = const [];
    inspected = 0;
    _notify();
    await _inspect(++_inspection);
  }

  Future<void> _inspect(int generation) async {
    final target = library;
    if (target == null) {
      step = ImportStep.source;
      error = 'Choose a library to import into first.';
      _notify();
      return;
    }

    final results = <ImportBook>[];
    for (final path in _paths) {
      try {
        results.add(await inspectBook(path, target.id, backend, files));
      } on DioException catch (e) {
        if (generation != _inspection) return;
        error = "The books couldn't be checked: ${uploadError(e)}";
        step = ImportStep.preview;
        _notify();
        return;
      }
      if (generation != _inspection) return;
      inspected = results.length;
      _notify();
    }
    books = markDuplicates(results);
    step = ImportStep.preview;
    _notify();
  }

  void backToSource() {
    _inspection++;
    step = ImportStep.source;
    books = const [];
    error = null;
    _notify();
  }

  Future<void> startImport() async {
    final target = library;
    if (target == null || readyCount == 0) return;

    final run = ImportRun();
    _run = run;
    step = ImportStep.importing;
    current = 0;
    total = readyCount;
    currentFraction = 0;
    scanning = false;
    _notify();

    report = await runImport(
      books: books,
      libraryId: target.id,
      backend: backend,
      run: run,
      scanRetryDelay: scanRetryDelay,
      onProgress: (index, count, book, fraction) {
        current = index;
        total = count;
        currentBook = book;
        currentFraction = fraction;
        _notify();
      },
      onScanning: () {
        scanning = true;
        _notify();
      },
    );
    _run = null;
    step = ImportStep.report;
    _notify();
  }

  void cancelImport() {
    _run?.cancel();
    _notify();
  }

  void startOver() {
    report = null;
    backToSource();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _inspection++;
    super.dispose();
  }
}
