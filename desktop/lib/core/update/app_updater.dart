import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'install_kind.dart';
import 'update_service.dart';

class UpdateException implements Exception {
  final String message;
  const UpdateException(this.message);
  @override
  String toString() => message;
}

/// Downloads a release for this install, checks it against the SHA-256
/// published with it, and installs it in place.
///
/// Only the app's own files are touched. Settings, saved servers, downloads
/// and the progress database live in the user's profile, not the app folder.
class AppUpdater {
  AppUpdater(this._service, {Future<void> Function(String executable)? relaunch})
      : _relaunch = relaunch ?? _startDetached;

  final UpdateService _service;
  final Future<void> Function(String executable) _relaunch;

  static const _backupSuffix = '.rekindle-old';
  static const _stagingName = '.rekindle-update';
  static const _leftoversName = '.rekindle-update-leftovers';

  /// Downloads the asset [target] updates from and verifies it. Throws an
  /// [UpdateException] if the release lacks it or its checksum, or the
  /// download doesn't match.
  Future<String> download(ReleaseInfo release, InstallTarget target,
      {void Function(double progress)? onProgress}) async {
    final name = target.kind.assetName;
    final asset = name == null ? null : release.asset(name);
    if (asset == null) {
      throw UpdateException('This release has no $name.');
    }
    final sums = release.asset('$name.sha256');
    if (sums == null) {
      throw UpdateException(
          "This release has no checksum for $name, so it can't be verified.");
    }

    final expected = parseChecksum(await _service.downloadText(sums));
    if (expected == null) {
      throw UpdateException('${sums.name} has no SHA-256 checksum in it.');
    }

    final path = await _service.downloadAsset(asset, onProgress: onProgress);
    final actual = await sha256OfFile(path);
    if (actual != expected) {
      await File(path).delete().catchError((_) => File(path));
      throw UpdateException(
          'The download of $name was corrupted (checksum mismatch). Try again.');
    }
    return path;
  }

  /// Installs [downloaded] over [target] and restarts Rekindle. On success the
  /// app is about to exit; the caller should quit straight after.
  Future<void> install(String downloaded, InstallTarget target) async {
    switch (target.kind) {
      case InstallKind.windowsInstaller:
        await _service.launchInstaller(downloaded, silent: true);
      case InstallKind.appImage:
        await replaceAppImage(downloaded, target.path);
        await _relaunch(target.executable);
      case InstallKind.windowsPortable || InstallKind.linuxPortable:
        await replaceFromZip(downloaded, target.path);
        await _relaunch(target.executable);
      default:
        throw const UpdateException("This copy of Rekindle can't update itself.");
    }
  }

  // ── AppImage ──────────────────────────────────────────────────────────────

  /// Puts [downloaded] in place of the AppImage at [appImage]. The new file is
  /// copied next to it first so the final rename is atomic; the running copy
  /// keeps its open file until it exits.
  static Future<void> replaceAppImage(String downloaded, String appImage) async {
    final staged = '$appImage.new';
    await File(downloaded).copy(staged);
    await _makeExecutable(staged);
    await File(staged).rename(appImage);
  }

  // ── Portable zip ──────────────────────────────────────────────────────────

  /// Replaces the files the zip ships inside [appDir]; anything else in the
  /// folder is left alone. Replaced files are renamed aside first (which also
  /// works for a running .exe on Windows) and the whole update is rolled back
  /// if any file can't be placed. Backups still in use are removed by
  /// [cleanupLeftovers] on the next start.
  static Future<void> replaceFromZip(String zipPath, String appDir) async {
    final root = p.normalize(p.absolute(appDir));
    final staging = p.join(root, _stagingName);
    final stagingDir = Directory(staging);
    if (stagingDir.existsSync()) stagingDir.deleteSync(recursive: true);
    stagingDir.createSync(recursive: true);

    final placed = <String>[];
    final backups = <(String, String)>[];
    // Held open while extracting. Left open, it would keep the downloaded zip
    // locked on Windows, so it could never be cleaned up.
    InputFileStream? input;
    try {
      input = InputFileStream(zipPath);
      final archive = ZipDecoder().decodeBuffer(input);
      final files = <(String rel, int mode)>[];
      for (final entry in archive.files) {
        if (!entry.isFile) continue;
        final rel = p.normalize(entry.name.replaceAll('\\', '/'));
        final dest = p.normalize(p.join(staging, rel));
        if (p.isAbsolute(rel) || !p.isWithin(staging, dest)) {
          throw UpdateException(
              'The update contains "${entry.name}", outside the app folder.');
        }
        Directory(p.dirname(dest)).createSync(recursive: true);
        final out = OutputFileStream(dest);
        entry.writeContent(out);
        await out.close();
        files.add((rel, entry.mode));
      }
      if (files.isEmpty) throw const UpdateException('The update is empty.');

      for (final (rel, mode) in files) {
        final target = p.join(root, rel);
        Directory(p.dirname(target)).createSync(recursive: true);
        if (File(target).existsSync()) {
          final backup = '$target$_backupSuffix';
          _tryDelete(backup);
          File(target).renameSync(backup);
          backups.add((target, backup));
        }
        File(p.join(staging, rel)).renameSync(target);
        placed.add(target);
        if (!Platform.isWindows && (mode & 0x40) != 0) {
          await _makeExecutable(target); // owner-executable in the zip
        }
      }
    } catch (_) {
      for (final f in placed) {
        _tryDelete(f);
      }
      for (final (target, backup) in backups.reversed) {
        try {
          File(backup).renameSync(target);
        } catch (_) {}
      }
      rethrow;
    } finally {
      await input?.close();
      try {
        if (stagingDir.existsSync()) stagingDir.deleteSync(recursive: true);
      } catch (_) {}
    }

    // Committed. Old files still in use (Windows) are recorded and removed on
    // the next start.
    final pending = [
      for (final (_, backup) in backups)
        if (!_tryDelete(backup)) backup,
    ];
    if (pending.isNotEmpty) {
      File(p.join(root, _leftoversName))
          .writeAsStringSync('${pending.join('\n')}\n', mode: FileMode.append);
    }
    // The executable must stay executable even if the zip lost its mode.
    if (!Platform.isWindows) {
      final exe = p.join(root, 'rekindle');
      if (File(exe).existsSync()) await _makeExecutable(exe);
    }
  }

  /// Removes backups an earlier update recorded because they were still in
  /// use. Reads only that list, never scans the folder, so it's cheap on
  /// every start even if the app was unzipped somewhere crowded.
  static void cleanupLeftovers(String appDir) {
    try {
      final list = File(p.join(appDir, _leftoversName));
      if (list.existsSync()) {
        final remaining = list
            .readAsLinesSync()
            .where((path) =>
                path.trim().isNotEmpty &&
                path.endsWith(_backupSuffix) && // only ever our own backups
                !_tryDelete(path))
            .toList();
        if (remaining.isEmpty) {
          list.deleteSync();
        } else {
          list.writeAsStringSync('${remaining.join('\n')}\n');
        }
      }
      final staging = Directory(p.join(appDir, _stagingName));
      if (staging.existsSync()) staging.deleteSync(recursive: true);
    } catch (_) {}
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Accepts a bare hash or `sha256sum` output ("hash  filename").
  static String? parseChecksum(String text) =>
      RegExp(r'\b[0-9a-fA-F]{64}\b').firstMatch(text)?.group(0)?.toLowerCase();

  static Future<String> sha256OfFile(String path) async =>
      (await sha256.bind(File(path).openRead()).first).toString();

  static Future<void> _makeExecutable(String path) async {
    if (Platform.isWindows) return;
    final r = await Process.run('chmod', ['755', path]);
    if (r.exitCode != 0) {
      throw UpdateException('Could not make $path executable: ${r.stderr}');
    }
  }

  /// Deletes [path] if it exists. False if it couldn't be (e.g. in use).
  static bool _tryDelete(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _startDetached(String executable) async {
    await Process.start(executable, const [],
        mode: ProcessStartMode.detached, workingDirectory: p.dirname(executable));
  }
}
