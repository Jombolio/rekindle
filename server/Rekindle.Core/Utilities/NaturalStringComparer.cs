namespace Rekindle.Core.Utilities;

/// Compares strings so embedded integers sort numerically rather than
/// lexicographically. "Chapter 2" &lt; "Chapter 10", "vol.9" &lt; "vol.10".
public sealed class NaturalStringComparer : IComparer<string?>
{
    public static readonly NaturalStringComparer Instance = new();

    public int Compare(string? x, string? y)
    {
        if (ReferenceEquals(x, y)) return 0;
        if (x is null) return -1;
        if (y is null) return 1;

        int ix = 0, iy = 0;
        while (ix < x.Length && iy < y.Length)
        {
            bool xDigit = char.IsAsciiDigit(x[ix]);
            bool yDigit = char.IsAsciiDigit(y[iy]);

            if (xDigit && yDigit)
            {
                long nx = 0, ny = 0;
                while (ix < x.Length && char.IsAsciiDigit(x[ix]))
                    nx = nx * 10 + (x[ix++] - '0');
                while (iy < y.Length && char.IsAsciiDigit(y[iy]))
                    ny = ny * 10 + (y[iy++] - '0');
                if (nx != ny) return nx.CompareTo(ny);
            }
            else
            {
                int cmp = char.ToLowerInvariant(x[ix])
                              .CompareTo(char.ToLowerInvariant(y[iy]));
                if (cmp != 0) return cmp;
                ix++; iy++;
            }
        }

        return x.Length.CompareTo(y.Length);
    }
}
