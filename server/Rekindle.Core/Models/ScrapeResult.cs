namespace Rekindle.Core.Models;

public enum ScrapeStatus
{
    /// <summary>No prior metadata existed; new data was written immediately.</summary>
    Created,
    /// <summary>Fresh data matched what was already stored; no write was performed.</summary>
    NoChange,
    /// <summary>Fresh data differs from stored data; awaiting admin confirmation before writing.</summary>
    Conflict,
}

public class ScrapeResult
{
    public ScrapeStatus Status   { get; init; }
    /// <summary>The freshly fetched (proposed) metadata.</summary>
    public MangaMetadata Data    { get; init; } = null!;
    /// <summary>The previously stored metadata. Only populated when <see cref="Status"/> is <see cref="ScrapeStatus.Conflict"/>.</summary>
    public MangaMetadata? Existing { get; init; }
}
