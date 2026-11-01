/// A semantic version (semver.org 2.0): MAJOR.MINOR.PATCH, an optional
/// pre-release such as "-beta.1", and optional build metadata ("+abc"), which
/// is ignored when comparing. Pre-releases sort before their release:
/// 1.5.0-beta.1 < 1.5.0-beta.2 < 1.5.0-rc.1 < 1.5.0.
///
/// Mirrors the server's `SemVersion`, so both agree on what is newer.
class SemVersion implements Comparable<SemVersion> {
  final int major;
  final int minor;
  final int patch;
  final String? preRelease;

  const SemVersion(this.major, this.minor, this.patch, [this.preRelease]);

  bool get isPreRelease => preRelease != null;

  static final _pattern = RegExp(
      r'^v?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$');

  /// Parses "1.5.0", "v1.5.0-beta.1" or "1.5.0-beta.1+21"; null otherwise.
  static SemVersion? tryParse(String? text) {
    if (text == null) return null;
    final m = _pattern.firstMatch(text.trim());
    if (m == null) return null;
    final pre = m.group(4);
    // semver forbids empty identifiers ("1.0.0-beta..1").
    if (pre != null && pre.split('.').any((p) => p.isEmpty)) return null;
    return SemVersion(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      pre,
    );
  }

  @override
  int compareTo(SemVersion other) {
    var c = major.compareTo(other.major);
    if (c != 0) return c;
    c = minor.compareTo(other.minor);
    if (c != 0) return c;
    c = patch.compareTo(other.patch);
    if (c != 0) return c;

    // A release outranks any pre-release of the same version.
    final a = preRelease;
    final b = other.preRelease;
    if (a == null) return b == null ? 0 : 1;
    if (b == null) return -1;

    final mine = a.split('.');
    final theirs = b.split('.');
    for (var i = 0; i < mine.length && i < theirs.length; i++) {
      c = _compareIdentifier(mine[i], theirs[i]);
      if (c != 0) return c;
    }
    // All shared identifiers equal: the longer pre-release ranks higher.
    return mine.length.compareTo(theirs.length);
  }

  static final _numeric = RegExp(r'^\d+$');

  /// Numeric identifiers compare numerically and rank below alphanumeric ones.
  static int _compareIdentifier(String a, String b) {
    final aNum = _numeric.hasMatch(a);
    final bNum = _numeric.hasMatch(b);
    if (aNum && bNum) return BigInt.parse(a).compareTo(BigInt.parse(b));
    if (aNum) return -1;
    if (bNum) return 1;
    return a.compareTo(b);
  }

  bool operator <(SemVersion other) => compareTo(other) < 0;
  bool operator >(SemVersion other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) =>
      other is SemVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch, preRelease);

  @override
  String toString() => preRelease == null
      ? '$major.$minor.$patch'
      : '$major.$minor.$patch-$preRelease';
}
