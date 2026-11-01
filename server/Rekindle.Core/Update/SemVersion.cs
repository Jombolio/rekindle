using System.Text.RegularExpressions;

namespace Rekindle.Core.Update;

/// <summary>
/// A semantic version (semver.org 2.0): MAJOR.MINOR.PATCH, an optional
/// pre-release such as "-beta.1", and optional build metadata ("+abc123"),
/// which is ignored when comparing. Pre-releases sort before their release:
/// 1.5.0-beta.1 &lt; 1.5.0-beta.2 &lt; 1.5.0-rc.1 &lt; 1.5.0.
/// </summary>
public sealed partial record SemVersion(int Major, int Minor, int Patch, string? PreRelease)
    : IComparable<SemVersion>
{
    public bool IsPreRelease => PreRelease is not null;

    [GeneratedRegex(@"^v?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$")]
    private static partial Regex Pattern();

    /// Parses "1.5.0", "v1.5.0-beta.1" or "1.5.0-beta.1+sha"; null otherwise.
    public static SemVersion? TryParse(string? text)
    {
        if (string.IsNullOrWhiteSpace(text)) return null;
        var m = Pattern().Match(text.Trim());
        if (!m.Success) return null;
        if (!int.TryParse(m.Groups[1].Value, out var major)
            || !int.TryParse(m.Groups[2].Value, out var minor)
            || !int.TryParse(m.Groups[3].Value, out var patch))
            return null;
        var pre = m.Groups[4].Success ? m.Groups[4].Value : null;
        // semver forbids empty identifiers ("1.0.0-beta..1").
        if (pre is not null && pre.Split('.').Any(string.IsNullOrEmpty)) return null;
        return new SemVersion(major, minor, patch, pre);
    }

    public int CompareTo(SemVersion? other)
    {
        if (other is null) return 1;
        var c = Major.CompareTo(other.Major);
        if (c != 0) return c;
        c = Minor.CompareTo(other.Minor);
        if (c != 0) return c;
        c = Patch.CompareTo(other.Patch);
        if (c != 0) return c;

        // A release outranks any pre-release of the same version.
        if (PreRelease is null) return other.PreRelease is null ? 0 : 1;
        if (other.PreRelease is null) return -1;

        var mine = PreRelease.Split('.');
        var theirs = other.PreRelease.Split('.');
        for (var i = 0; i < Math.Min(mine.Length, theirs.Length); i++)
        {
            c = CompareIdentifier(mine[i], theirs[i]);
            if (c != 0) return c;
        }
        // All shared identifiers equal: the longer pre-release ranks higher.
        return mine.Length.CompareTo(theirs.Length);
    }

    /// Numeric identifiers compare numerically and rank below alphanumeric ones.
    private static int CompareIdentifier(string a, string b)
    {
        var aNumeric = a.All(char.IsAsciiDigit);
        var bNumeric = b.All(char.IsAsciiDigit);
        if (aNumeric && bNumeric)
        {
            // Compare by length first so arbitrarily large numbers work.
            var trimmedA = a.TrimStart('0');
            var trimmedB = b.TrimStart('0');
            var len = trimmedA.Length.CompareTo(trimmedB.Length);
            return len != 0 ? len : string.CompareOrdinal(trimmedA, trimmedB);
        }
        if (aNumeric) return -1;
        if (bNumeric) return 1;
        return string.CompareOrdinal(a, b);
    }

    public static bool operator <(SemVersion a, SemVersion b) => a.CompareTo(b) < 0;
    public static bool operator >(SemVersion a, SemVersion b) => a.CompareTo(b) > 0;
    public static bool operator <=(SemVersion a, SemVersion b) => a.CompareTo(b) <= 0;
    public static bool operator >=(SemVersion a, SemVersion b) => a.CompareTo(b) >= 0;

    public override string ToString() =>
        PreRelease is null ? $"{Major}.{Minor}.{Patch}" : $"{Major}.{Minor}.{Patch}-{PreRelease}";
}
