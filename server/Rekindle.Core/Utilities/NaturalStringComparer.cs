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
                // Compare digit runs by value without parsing to a fixed-width
                // integer, so a 19+ digit run can't overflow and misorder.
                int sx = ix, sy = iy;
                while (ix < x.Length && char.IsAsciiDigit(x[ix])) ix++;
                while (iy < y.Length && char.IsAsciiDigit(y[iy])) iy++;

                // Skip leading zeros, then longer remaining run = larger number;
                // equal length falls back to lexicographic digit comparison.
                int zx = sx; while (zx < ix - 1 && x[zx] == '0') zx++;
                int zy = sy; while (zy < iy - 1 && y[zy] == '0') zy++;
                int lenX = ix - zx, lenY = iy - zy;
                if (lenX != lenY) return lenX.CompareTo(lenY);
                for (int k = 0; k < lenX; k++)
                {
                    int cmp = x[zx + k].CompareTo(y[zy + k]);
                    if (cmp != 0) return cmp;
                }
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
