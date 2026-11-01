import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rekindle/core/update/app_updater.dart';
import 'package:rekindle/core/update/auto_update.dart';
import 'package:rekindle/core/update/install_kind.dart';
import 'package:rekindle/core/update/update_service.dart';

void main() {
  group('detectInstall', () {
    InstallTarget detect({
      bool windows = false,
      bool linux = false,
      bool release = true,
      String exe = '/apps/rekindle/rekindle',
      Map<String, String> env = const {},
      Set<String> files = const {},
      bool writable = true,
    }) =>
        detectInstall(
          isWindows: windows,
          isLinux: linux,
          releaseBuild: release,
          executable: exe,
          environment: env,
          fileExists: files.contains,
          isWritable: (_) => writable,
        );

    test('a development build never updates itself', () {
      expect(detect(linux: true, release: false).kind, InstallKind.unsupported);
    });

    test('Windows with the uninstaller is an installer install', () {
      // Paths built with the host's separators: the code uses package:path,
      // which follows Windows rules on Windows.
      final dir = p.join('Program Files', 'Rekindle');
      final t = detect(
          windows: true,
          exe: p.join(dir, 'rekindle.exe'),
          files: {p.join(dir, 'unins000.exe')});
      expect(t.kind, InstallKind.windowsInstaller);
      expect(t.kind.assetName, 'Rekindle-windows-x64Setup.exe');
    });

    test('Windows without it is the portable zip', () {
      final t = detect(windows: true, exe: p.join('Apps', 'Rekindle', 'rekindle.exe'));
      expect(t.kind, InstallKind.windowsPortable);
      expect(t.kind.assetName, 'RekindleClient-windows-x64.zip');
    });

    test('an AppImage updates the AppImage file itself', () {
      const image = '/home/me/Apps/Rekindle.AppImage';
      final t = detect(
          linux: true,
          exe: '/tmp/.mount_Rekind/rekindle',
          env: {'APPIMAGE': image},
          files: {image});
      expect(t.kind, InstallKind.appImage);
      expect(t.path, image);
      expect(t.executable, image);
    });

    test('a Flatpak is detected and not installed in-app', () {
      final t = detect(
          linux: true, exe: '/app/rekindle/rekindle', env: {'FLATPAK_ID': 'x'});
      expect(t.kind, InstallKind.flatpak);
      expect(t.kind.installsInApp, isFalse);
    });

    test("a folder the user can't write (AUR, /opt) is package-managed", () {
      final t = detect(
          linux: true, exe: '/opt/rekindle/rekindle', writable: false);
      expect(t.kind, InstallKind.packageManaged);
      expect(t.kind.installsInApp, isFalse);
    });

    test('a writable folder on Linux is the portable zip', () {
      final t = detect(linux: true, exe: '/home/me/Rekindle/rekindle');
      expect(t.kind, InstallKind.linuxPortable);
      expect(t.path, '/home/me/Rekindle');
    });
  });

  group('automatic check', () {
    final now = DateTime(2026, 11, 2, 12);

    test('runs when enabled and never checked', () {
      expect(shouldAutoCheck(enabled: true, lastCheck: null, now: now), isTrue);
    });

    test('runs at most once a day', () {
      expect(
          shouldAutoCheck(
              enabled: true,
              lastCheck: now.subtract(const Duration(hours: 3)),
              now: now),
          isFalse);
      expect(
          shouldAutoCheck(
              enabled: true,
              lastCheck: now.subtract(const Duration(hours: 25)),
              now: now),
          isTrue);
    });

    test('never runs when switched off', () {
      expect(shouldAutoCheck(enabled: false, lastCheck: null, now: now),
          isFalse);
    });

    test('a clock set backwards does not block checks', () {
      expect(
          shouldAutoCheck(
              enabled: true,
              lastCheck: now.add(const Duration(days: 30)),
              now: now),
          isTrue);
    });

    UpdateCheckResult available(String version) => UpdateCheckResult(
          status: UpdateStatus.updateAvailable,
          currentVersion: '1.5.0-beta.3',
          release: ReleaseInfo.fromJson({'tag_name': 'v$version', 'assets': []}),
        );

    test('offers an update unless that version was skipped', () {
      expect(shouldOfferAutomatically(available('1.5.0'), null), isTrue);
      expect(shouldOfferAutomatically(available('1.5.0'), '1.5.0'), isFalse);
      expect(shouldOfferAutomatically(available('1.5.1'), '1.5.0'), isTrue,
          reason: 'skipping one version does not skip the next');
    });
  });

  group('AppUpdater.replaceFromZip', () {
    late Directory root;
    late String app;

    setUp(() {
      root = Directory.systemTemp.createTempSync('rekindle-zip-');
      app = p.join(root.path, 'Rekindle');
      Directory(p.join(app, 'data', 'flutter_assets')).createSync(recursive: true);
      Directory(p.join(app, 'lib')).createSync();
      File(p.join(app, 'rekindle')).writeAsStringSync('old binary');
      File(p.join(app, 'lib', 'libapp.so')).writeAsStringSync('old lib');
      File(p.join(app, 'data', 'flutter_assets', 'version.json'))
          .writeAsStringSync('{"version":"1.5.0-beta.3"}');
      File(p.join(app, 'my-notes.txt')).writeAsStringSync('mine');
    });

    tearDown(() => root.deleteSync(recursive: true));

    String zip(Map<String, String> files, {Map<String, int> modes = const {}}) {
      final archive = Archive();
      files.forEach((name, content) {
        final bytes = utf8.encode(content);
        final f = ArchiveFile(name, bytes.length, bytes);
        if (modes[name] != null) f.mode = modes[name]!;
        archive.addFile(f);
      });
      final path = p.join(root.path, 'update-${files.length}.zip');
      File(path).writeAsBytesSync(ZipEncoder().encode(archive)!);
      return path;
    }

    String read(String rel) => File(p.join(app, rel)).readAsStringSync();

    test('replaces shipped files and keeps everything else', () async {
      await AppUpdater.replaceFromZip(
          zip({
            'rekindle': 'new binary',
            'lib/libapp.so': 'new lib',
            'data/flutter_assets/version.json': '{"version":"1.5.0"}',
            'lib/libnew.so': 'added',
          }, modes: {'rekindle': 0x1ED /* 0755 */}),
          app);

      expect(read('rekindle'), 'new binary');
      expect(read('lib/libapp.so'), 'new lib');
      expect(read('lib/libnew.so'), 'added');
      expect(read('data/flutter_assets/version.json'), '{"version":"1.5.0"}');
      expect(read('my-notes.txt'), 'mine');
      expect(
          Directory(app)
              .listSync(recursive: true)
              .map((e) => e.path)
              .where((n) => n.contains('.rekindle')),
          isEmpty,
          reason: 'no backups or staging left behind');
    });

    test('keeps the executable executable', () async {
      if (Platform.isWindows) return;
      await AppUpdater.replaceFromZip(zip({'rekindle': 'new'}), app);

      final mode = File(p.join(app, 'rekindle')).statSync().mode;
      expect(mode & 0x40, isNot(0), reason: 'owner execute bit');
    });

    test('rejects entries outside the app folder and changes nothing',
        () async {
      final bad = zip({'rekindle': 'new', '../escaped.txt': 'evil'});

      await expectLater(
          AppUpdater.replaceFromZip(bad, app), throwsA(isA<UpdateException>()));
      expect(File(p.join(root.path, 'escaped.txt')).existsSync(), isFalse);
      expect(read('rekindle'), 'old binary');
    });

    test('rolls everything back when a file cannot be placed', () async {
      // A folder where the update has a file makes placing it fail part-way.
      Directory(p.join(app, 'lib', 'blocker.so')).createSync();
      final update = zip({
        'rekindle': 'new binary',
        'lib/libapp.so': 'new lib',
        'lib/blocker.so': 'x',
      });

      await expectLater(AppUpdater.replaceFromZip(update, app), throwsA(anything));
      expect(read('rekindle'), 'old binary');
      expect(read('lib/libapp.so'), 'old lib');
    });

    test('cleanupLeftovers deletes only what an update recorded', () {
      final leftover = p.join(app, 'rekindle.exe.rekindle-old');
      File(leftover).writeAsStringSync('old');
      final unrelated = p.join(app, 'my-notes.txt');
      File(p.join(app, '.rekindle-update-leftovers'))
          .writeAsStringSync('$leftover\n$unrelated\n');

      AppUpdater.cleanupLeftovers(app);

      expect(File(leftover).existsSync(), isFalse);
      expect(File(unrelated).existsSync(), isTrue,
          reason: 'only .rekindle-old backups are ever deleted');
      expect(File(p.join(app, '.rekindle-update-leftovers')).existsSync(),
          isFalse);
    });
  });

  test('replaceAppImage swaps the file and makes it executable', () async {
    final dir = Directory.systemTemp.createTempSync('rekindle-appimage-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final current = p.join(dir.path, 'Rekindle.AppImage');
    final downloaded = p.join(dir.path, 'download.AppImage');
    File(current).writeAsStringSync('old');
    File(downloaded).writeAsStringSync('new');

    await AppUpdater.replaceAppImage(downloaded, current);

    expect(File(current).readAsStringSync(), 'new');
    expect(File('$current.new').existsSync(), isFalse);
    if (!Platform.isWindows) {
      expect(File(current).statSync().mode & 0x40, isNot(0));
    }
  });

  group('AppUpdater.download', () {
    const zipName = 'RekindleClient-linux-x64.zip';
    final payload = utf8.encode('the update');
    final goodHash = sha256.convert(payload).toString();

    ReleaseInfo release({bool withSums = true}) => ReleaseInfo.fromJson({
          'tag_name': 'v1.5.0',
          'assets': [
            {'name': zipName, 'browser_download_url': 'https://x/$zipName', 'size': payload.length},
            if (withSums)
              {'name': '$zipName.sha256', 'browser_download_url': 'https://x/$zipName.sha256', 'size': 90},
          ],
        });

    AppUpdater updater(String sums) => AppUpdater(UpdateService(
        dio: Dio()..httpClientAdapter = _Files({
          '$zipName.sha256': utf8.encode(sums),
          zipName: payload,
        })));

    const target = InstallTarget(InstallKind.linuxPortable, '/x', '/x/rekindle');

    test('returns the verified download', () async {
      final path =
          await updater('$goodHash  $zipName\n').download(release(), target);
      expect(File(path).readAsBytesSync(), payload);
    });

    test('refuses a checksum mismatch', () async {
      await expectLater(
          updater('${'0' * 64}  $zipName').download(release(), target),
          throwsA(isA<UpdateException>()
              .having((e) => e.message, 'message', contains('checksum'))));
    });

    test('refuses a release without a checksum', () async {
      await expectLater(
          updater('').download(release(withSums: false), target),
          throwsA(isA<UpdateException>()
              .having((e) => e.message, 'message', contains("can't be verified"))));
    });
  });
}

/// Serves fixed bodies by file name.
class _Files implements HttpClientAdapter {
  _Files(this.files);
  final Map<String, List<int>> files;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final body = files[p.basename(options.uri.path)];
    if (body == null) return ResponseBody.fromString('missing', 404);
    return ResponseBody.fromBytes(body, 200,
        headers: {Headers.contentLengthHeader: ['${body.length}']});
  }

  @override
  void close({bool force = false}) {}
}
