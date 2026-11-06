namespace Rekindle.Core.Models;

/// <summary>
/// How often a library is scanned on its own. A library without one is only
/// scanned when someone asks.
/// </summary>
public class ScanSchedule
{
    /// <summary>The shortest and longest gaps allowed between scheduled scans.</summary>
    public const int MinIntervalHours = 1;
    public const int MaxIntervalHours = 24 * 30;

    public string LibraryId { get; set; } = string.Empty;
    public int IntervalHours { get; set; }

    /// <summary>When a scheduled scan last started, if one has.</summary>
    public DateTime? LastRunAt { get; set; }

    /// <summary>When the next scheduled scan is due.</summary>
    public DateTime NextRunAt { get; set; }

    public bool IsDue(DateTime nowUtc) => NextRunAt <= nowUtc;

    /// <summary>
    /// When the scan after one that started at <paramref name="startedUtc"/> and
    /// finished at <paramref name="finishedUtc"/> is due: one interval after it
    /// started, so scans keep their rhythm, unless the scan ran longer than the
    /// interval, when the next waits a full interval from its end rather than
    /// starting straight away.
    /// </summary>
    public static DateTime NextAfter(DateTime startedUtc, DateTime finishedUtc, int intervalHours)
    {
        var interval = TimeSpan.FromHours(intervalHours);
        var next = startedUtc + interval;
        return next > finishedUtc ? next : finishedUtc + interval;
    }

    /// <summary>
    /// When the first scan is due under a new or changed interval: one interval
    /// after the last scheduled scan, or from now if there hasn't been one, and
    /// never in the past.
    /// </summary>
    public static DateTime FirstDue(DateTime? lastRunUtc, DateTime nowUtc, int intervalHours)
    {
        var next = (lastRunUtc ?? nowUtc) + TimeSpan.FromHours(intervalHours);
        return next > nowUtc ? next : nowUtc;
    }
}
