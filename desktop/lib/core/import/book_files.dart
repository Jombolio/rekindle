import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../epub/epub_parser.dart';
import '../utils/natural_sort.dart';

/// Everything the import reads from the user's disk or Kindle. Read only: nothing
/// here writes to the folder or the device.
class BookFiles {
  const BookFiles();

  static const extensions = {'mobi', 'azw', 'azw3', 'kfx', 'epub'};

  /// Only the start of a Kindle file is sent to be checked. The first record,
  /// which is all that's needed, follows a table of 8 bytes per record.
  static const headBytes = 256 * 1024;

  static String extensionOf(String path) =>
      p.extension(path).replaceFirst('.', '').toLowerCase();

  /// The books under [root], in natural order. Folders that can't be read are
  /// passed over, since a device or disk commonly has a few.
  Future<List<String>> findBooks(String root) async {
    final found = <String>[];
    await _collect(Directory(root), found);
    found.sort(naturalCompare);
    return found;
  }

  Future<void> _collect(Directory dir, List<String> found) async {
    final subfolders = <Directory>[];
    try {
      await for (final entry in dir.list(followLinks: false)) {
        if (entry is File) {
          if (extensions.contains(extensionOf(entry.path))) {
            found.add(entry.path);
          }
        } else if (entry is Directory && !_isSkipped(entry.path)) {
          subfolders.add(entry);
        }
      }
    } on FileSystemException {
      return;
    }
    for (final folder in subfolders) {
      await _collect(folder, found);
    }
  }

  /// .sdr folders hold a Kindle's reading position and notes for a book, and
  /// their files aren't books. The rest are system folders and trash.
  static bool _isSkipped(String path) {
    final name = p.basename(path).toLowerCase();
    return name.endsWith('.sdr') ||
        name.startsWith('.') ||
        name.startsWith(r'$') ||
        name == 'system volume information';
  }

  Future<Uint8List> readHead(String path) async {
    final chunks = BytesBuilder(copy: false);
    await for (final chunk in File(path).openRead(0, headBytes)) {
      chunks.add(chunk);
    }
    return chunks.takeBytes();
  }

  Future<EpubInfo> readEpubInfo(String path) =>
      Isolate.run(() => EpubInfo.read(path));

  /// The documents folder of each Kindle connected over USB. A folder called
  /// documents alone would match plenty of ordinary drives, so its system folder
  /// has to be there too.
  Future<List<String>> findKindles({List<String>? mountPoints}) async {
    final mounts = mountPoints ?? await _mountPoints();
    final results = await Future.wait(mounts.map((mount) async {
      final documents = p.join(mount, 'documents');
      try {
        final isKindle = await _existsWithin(documents) &&
            await _existsWithin(p.join(mount, 'system'));
        return isKindle ? documents : null;
      } on FileSystemException {
        return null;
      }
    }));
    return results.whereType<String>().toList();
  }

  /// A network drive that's gone away can take a long time to say so.
  static Future<bool> _existsWithin(String path) => Directory(path)
      .exists()
      .timeout(const Duration(seconds: 2), onTimeout: () => false);

  static Future<List<String>> _mountPoints() async {
    if (Platform.isWindows) {
      // From D: so as not to spin up floppies or look at the system drive.
      return [
        for (var letter = 0x44; letter <= 0x5A; letter++)
          '${String.fromCharCode(letter)}:\\',
      ];
    }

    final user = Platform.environment['USER'];
    final mounts = <String>[];
    for (final parent in [
      if (user != null) '/run/media/$user',
      if (user != null) '/media/$user',
      '/media',
      '/mnt',
    ]) {
      try {
        await for (final entry in Directory(parent).list(followLinks: false)) {
          if (entry is Directory) mounts.add(entry.path);
        }
      } on FileSystemException {
        continue;
      }
    }
    return mounts;
  }
}

/// A readable name for a book with no metadata. Kindle ends its file names with
/// the book's store id, as in My_Book_B00ABCDEFG_EBOK.azw.
String titleFromFileName(String fileName) {
  final name = p
      .basenameWithoutExtension(fileName)
      .replaceFirst(RegExp(r'[_-]B[0-9A-Z]{9}(_[A-Z]{4})?$'), '')
      .replaceAll('_', ' ')
      .trim();
  return name.isEmpty ? fileName : name;
}

/// What an EPUB's own files say about it.
class EpubInfo {
  final String? title;
  final String? author;
  final bool isProtected;
  final bool isReadable;

  const EpubInfo({
    this.title,
    this.author,
    this.isProtected = false,
    this.isReadable = true,
  });

  // The two ways of disguising embedded fonts: encryption.xml lists these in
  // books with no DRM at all.
  static const _fontAlgorithms = {
    'http://www.idpf.org/2008/embedding',
    'http://ns.adobe.com/pdf/enc#rc',
  };

  static EpubInfo read(String path) {
    InputFileStream? input;
    try {
      input = InputFileStream(path);
      final archive = ZipDecoder().decodeBuffer(input);
      final entries = <String, ArchiveFile>{
        for (final f in archive.files)
          if (f.isFile) EpubParser.normalizePath(f.name).toLowerCase(): f,
      };
      final isProtected = _isProtected(entries);

      try {
        final container = _xml(entries['meta-inf/container.xml']);
        final opfPath = container
            ?.findAllElements('rootfile')
            .firstOrNull
            ?.getAttribute('full-path');
        final opf = opfPath == null
            ? null
            : _xml(entries[EpubParser.normalizePath(opfPath).toLowerCase()]);
        if (opf == null) {
          return EpubInfo(isProtected: isProtected, isReadable: isProtected);
        }
        return EpubInfo(
          title: _firstText(opf, 'title'),
          author: _firstText(opf, 'creator'),
          isProtected: isProtected,
        );
      } on XmlException {
        return EpubInfo(isProtected: isProtected, isReadable: isProtected);
      }
    } on FileSystemException {
      return const EpubInfo(isReadable: false);
    } on ArchiveException {
      return const EpubInfo(isReadable: false);
    } on FormatException {
      return const EpubInfo(isReadable: false);
    } on RangeError {
      return const EpubInfo(isReadable: false);
    } finally {
      input?.closeSync();
    }
  }

  static bool _isProtected(Map<String, ArchiveFile> entries) {
    if (entries.containsKey('meta-inf/license.lcpl')) return true;

    final encryption = entries['meta-inf/encryption.xml'];
    if (encryption == null) return false;
    try {
      final methods = _xml(encryption)!
          .findAllElements('EncryptionMethod', namespace: '*')
          .map((e) => e.getAttribute('Algorithm')?.toLowerCase());
      return methods.any((a) => !_fontAlgorithms.contains(a));
    } on XmlException {
      // It says something is encrypted, and can't be read to say it's only fonts.
      return true;
    }
  }

  static XmlDocument? _xml(ArchiveFile? entry) {
    if (entry == null) return null;
    final bytes = Uint8List.fromList(entry.content as List<int>);
    return XmlDocument.parse(EpubParser.decodeText(bytes));
  }

  static String? _firstText(XmlDocument opf, String name) {
    final text =
        opf.findAllElements(name, namespace: '*').firstOrNull?.innerText.trim();
    return text == null || text.isEmpty ? null : text;
  }
}
