import 'dart:io';

import 'package:path/path.dart' as p;

/// How this copy of Rekindle was installed, which decides how it updates.
enum InstallKind {
  /// Windows, installed with the Inno Setup installer: run the new installer.
  windowsInstaller,

  /// Windows, unzipped from the portable zip: replace the files in place.
  windowsPortable,

  /// Linux AppImage: swap the AppImage file.
  appImage,

  /// Linux, unzipped from the portable zip: replace the files in place.
  linuxPortable,

  /// Flatpak: the app can't replace itself from inside its sandbox.
  flatpak,

  /// Installed by a package manager (e.g. the AUR's rekindle-bin into /opt),
  /// or anywhere this user can't write: the package manager updates it.
  packageManaged,

  /// Windows, a portable copy in a folder this user can't write to: nothing can
  /// replace its files until it's moved.
  readOnlyFolder,

  /// A development build, or a platform without a published build.
  unsupported;

  /// Whether Rekindle can install the update itself and restart.
  bool get installsInApp => switch (this) {
        windowsInstaller || windowsPortable || appImage || linuxPortable =>
          true,
        _ => false,
      };

  /// The release asset this kind of install updates from.
  String? get assetName => switch (this) {
        windowsInstaller => 'Rekindle-windows-x64Setup.exe',
        windowsPortable => 'RekindleClient-windows-x64.zip',
        appImage => 'RekindleClient-linux-x86_64.AppImage',
        linuxPortable || packageManaged => 'RekindleClient-linux-x64.zip',
        readOnlyFolder => 'RekindleClient-windows-x64.zip',
        flatpak => 'RekindleClient-linux-x86_64.flatpak',
        unsupported => null,
      };
}

/// What was detected: the kind, and the file or folder an update replaces.
class InstallTarget {
  final InstallKind kind;

  /// The AppImage file, or the app folder for the other kinds.
  final String path;

  /// The executable to start after updating.
  final String executable;

  const InstallTarget(this.kind, this.path, this.executable);
}

/// Works out how this copy was installed. The parameters exist for tests; by
/// default they read the real process, environment and file system.
InstallTarget detectInstall({
  bool? isWindows,
  bool? isLinux,
  bool releaseBuild = const bool.fromEnvironment('dart.vm.product'),
  String? executable,
  Map<String, String>? environment,
  bool Function(String path)? fileExists,
  bool Function(String dir)? isWritable,
}) {
  final windows = isWindows ?? Platform.isWindows;
  final linux = isLinux ?? Platform.isLinux;
  final exe = executable ?? Platform.resolvedExecutable;
  final env = environment ?? Platform.environment;
  final exists = fileExists ?? (path) => File(path).existsSync();
  final writable = isWritable ?? _canWrite;
  final dir = p.dirname(exe);

  // A `flutter run` build lives in the build output; "updating" it would
  // overwrite what the developer just built.
  if (!releaseBuild) return InstallTarget(InstallKind.unsupported, dir, exe);

  if (windows) {
    // Inno Setup leaves its uninstaller next to the app. Checked before the
    // folder is: Program Files isn't writable, and doesn't need to be, because
    // the installer asks for elevation itself.
    if (exists(p.join(dir, 'unins000.exe'))) {
      return InstallTarget(InstallKind.windowsInstaller, dir, exe);
    }
    final kind =
        writable(dir) ? InstallKind.windowsPortable : InstallKind.readOnlyFolder;
    return InstallTarget(kind, dir, exe);
  }

  if (linux) {
    final appImage = env['APPIMAGE'];
    if (appImage != null && appImage.isNotEmpty && exists(appImage)) {
      return InstallTarget(InstallKind.appImage, appImage, appImage);
    }
    if ((env['FLATPAK_ID'] ?? '').isNotEmpty || exists('/.flatpak-info')) {
      return InstallTarget(InstallKind.flatpak, dir, exe);
    }
    if (!writable(dir)) {
      return InstallTarget(InstallKind.packageManaged, dir, exe);
    }
    return InstallTarget(InstallKind.linuxPortable, dir, exe);
  }

  return InstallTarget(InstallKind.unsupported, dir, exe);
}

bool _canWrite(String dir) {
  try {
    final probe = File(p.join(dir, '.rekindle-write-test'));
    probe.writeAsStringSync('');
    probe.deleteSync();
    return true;
  } on FileSystemException {
    return false;
  }
}
