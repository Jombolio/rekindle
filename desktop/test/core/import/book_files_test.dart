import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rekindle/core/import/book_files.dart';

void main() {
  late Directory root;
  const files = BookFiles();

  setUp(() => root = Directory.systemTemp.createTempSync('rekindle-import'));
  tearDown(() => root.deleteSync(recursive: true));

  void touch(String relative, [List<int> content = const [1]]) {
    File(p.join(root.path, relative))
      ..createSync(recursive: true)
      ..writeAsBytesSync(content);
  }

  group('findBooks', () {
    test('finds every importable format, in any folder and case', () async {
      touch('a.mobi');
      touch('b.AZW');
      touch('nested/deep/c.azw3');
      touch('nested/d.kfx');
      touch('e.epub');

      final found = await files.findBooks(root.path);

      expect(found.map(p.basename),
          unorderedEquals(['a.mobi', 'b.AZW', 'c.azw3', 'd.kfx', 'e.epub']));
    });

    test('ignores other files', () async {
      touch('a.pdf');
      touch('a.mbp');
      touch('a.apnx');
      touch('a.azw3f');
      touch('a.mobi.txt');

      expect(await files.findBooks(root.path), isEmpty);
    });

    test('skips sidecar, hidden and system folders', () async {
      touch('real.azw3');
      touch('real.sdr/real.azw3');
      touch('REAL.SDR/other.mobi');
      touch('.Trash-1000/deleted.mobi');
      touch(r'$RECYCLE.BIN/deleted.mobi');
      touch('System Volume Information/x.mobi');

      final found = await files.findBooks(root.path);

      expect(found.map(p.basename), ['real.azw3']);
    });

    test('sorts naturally', () async {
      touch('Book 10.mobi');
      touch('Book 2.mobi');

      final found = await files.findBooks(root.path);

      expect(found.map(p.basename), ['Book 2.mobi', 'Book 10.mobi']);
    });

    test('finds nothing in a folder that does not exist', () async {
      expect(await files.findBooks(p.join(root.path, 'gone')), isEmpty);
    });

    test('may be pointed at a folder a filter would otherwise skip', () async {
      touch('.hidden/book.mobi');

      final found = await files.findBooks(p.join(root.path, '.hidden'));

      expect(found.map(p.basename), ['book.mobi']);
    });
  });

  group('findKindles', () {
    test('offers the documents folder of a drive that looks like a Kindle',
        () async {
      Directory(p.join(root.path, 'kindle', 'documents'))
          .createSync(recursive: true);
      Directory(p.join(root.path, 'kindle', 'system'))
          .createSync(recursive: true);

      final found =
          await files.findKindles(mountPoints: [p.join(root.path, 'kindle')]);

      expect(found, [p.join(root.path, 'kindle', 'documents')]);
    });

    test('does not offer an ordinary drive with a documents folder', () async {
      Directory(p.join(root.path, 'usb', 'documents'))
          .createSync(recursive: true);

      final found =
          await files.findKindles(mountPoints: [p.join(root.path, 'usb')]);

      expect(found, isEmpty);
    });

    test('passes over mount points that are not there', () async {
      final found =
          await files.findKindles(mountPoints: [p.join(root.path, 'gone')]);

      expect(found, isEmpty);
    });
  });

  group('readHead', () {
    test('reads only the start of a large file', () async {
      touch('big.mobi', List.filled(BookFiles.headBytes + 100, 7));

      final head = await files.readHead(p.join(root.path, 'big.mobi'));

      expect(head.length, BookFiles.headBytes);
    });

    test('reads all of a small file', () async {
      touch('small.mobi', [1, 2, 3]);

      expect(await files.readHead(p.join(root.path, 'small.mobi')), [1, 2, 3]);
    });
  });

  group('titleFromFileName', () {
    test('removes the store id Kindle adds', () {
      expect(titleFromFileName('My_Book_B00ABCDEFG_EBOK.azw'), 'My Book');
      expect(titleFromFileName('Dune-B00B7NPRY8.azw3'), 'Dune');
    });

    test('leaves ordinary names alone', () {
      expect(titleFromFileName('A Good Book.mobi'), 'A Good Book');
    });

    test('never returns nothing', () {
      expect(titleFromFileName('_.kfx'), '_.kfx');
    });
  });

  group('EpubInfo', () {
    const container =
        '<container><rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles></container>';
    const opf =
        '<package xmlns:dc="http://purl.org/dc/elements/1.1/"><metadata><dc:title>The Title</dc:title><dc:creator>The Author</dc:creator><dc:creator>Second</dc:creator></metadata></package>';

    String epub(Map<String, String> entries) {
      final archive = Archive();
      entries.forEach((name, text) {
        final data = utf8.encode(text);
        archive.addFile(ArchiveFile(name, data.length, data));
      });
      final path = p.join(root.path, 'book.epub');
      File(path).writeAsBytesSync(ZipEncoder().encode(archive)!);
      return path;
    }

    String encryption(String algorithm) => '''
<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container" xmlns:enc="http://www.w3.org/2001/04/xmlenc#">
  <enc:EncryptedData><enc:EncryptionMethod Algorithm="$algorithm"/></enc:EncryptedData>
</encryption>''';

    test('reads the title and author', () {
      final info = EpubInfo.read(epub({
        'META-INF/container.xml': container,
        'OPS/book.opf': opf,
      }));

      expect(info.isReadable, isTrue);
      expect(info.isProtected, isFalse);
      expect(info.title, 'The Title');
      expect(info.author, 'The Author');
    });

    test('calls a book with encrypted content protected', () {
      final info = EpubInfo.read(epub({
        'META-INF/container.xml': container,
        'META-INF/encryption.xml':
            encryption('http://www.w3.org/2001/04/xmlenc#aes128-cbc'),
        'OPS/book.opf': opf,
      }));

      expect(info.isProtected, isTrue);
      expect(info.title, 'The Title');
    });

    for (final algorithm in [
      'http://www.idpf.org/2008/embedding',
      'http://ns.adobe.com/pdf/enc#RC',
    ]) {
      test('does not count font obfuscation as DRM: $algorithm', () {
        final info = EpubInfo.read(epub({
          'META-INF/container.xml': container,
          'META-INF/encryption.xml': encryption(algorithm),
          'OPS/book.opf': opf,
        }));

        expect(info.isProtected, isFalse);
      });
    }

    test('calls a book with a licence file protected', () {
      final info = EpubInfo.read(epub({
        'META-INF/container.xml': container,
        'META-INF/license.lcpl': '{}',
        'OPS/book.opf': opf,
      }));

      expect(info.isProtected, isTrue);
    });

    test('assumes the worst of an encryption file it cannot read', () {
      final info = EpubInfo.read(epub({
        'META-INF/container.xml': container,
        'META-INF/encryption.xml': '<not xml',
        'OPS/book.opf': opf,
      }));

      expect(info.isProtected, isTrue);
    });

    test('still reports protection when the metadata is unreadable', () {
      final info = EpubInfo.read(epub({
        'META-INF/encryption.xml':
            encryption('http://www.w3.org/2001/04/xmlenc#aes128-cbc'),
      }));

      expect(info.isProtected, isTrue);
      expect(info.title, isNull);
    });

    test('calls a zip with no book in it unreadable', () {
      expect(EpubInfo.read(epub({'readme.txt': 'hello'})).isReadable, isFalse);
    });

    test('calls a file that is not a zip unreadable', () {
      touch('fake.epub', utf8.encode('this is not a zip file at all'));

      expect(EpubInfo.read(p.join(root.path, 'fake.epub')).isReadable, isFalse);
    });

    test('calls a missing file unreadable', () {
      expect(EpubInfo.read(p.join(root.path, 'gone.epub')).isReadable, isFalse);
    });
  });
}
