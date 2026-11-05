import 'package:flutter/painting.dart';

import 'epub_parser.dart';

/// A book the reader can show, wherever it comes from: a downloaded file, or
/// streamed from the server a chapter at a time.
abstract class ReaderBook {
  int get chapterCount;
  String chapterTitle(int index);

  /// Index of the chapter stored at [path], or null if it isn't one.
  int? chapterIndexOf(String path);

  Future<EpubChapter> loadChapter(int index);

  /// An image from the book by its path inside the EPUB, or null if unavailable.
  ImageProvider<Object>? imageProvider(String path);
}
