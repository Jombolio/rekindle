namespace Rekindle.Core.Models;

public enum ScrapeStatus
{
    /// <summary>No prior metadata existed; new data was written immediately.</summary>
    Created,
    /// <summary>Fresh data matched what was already stored; no write was performed.</summary>
    NoChange,
    /// <summary>Fresh data differs from stored data; awaiting admin confirmation before writing.</summary>
    Conflict,
    /// <summary>No API key is configured for this library type.</summary>
    NoApiKey,
    /// <summary>A key is configured but no matching title was found on any source.</summary>
    NotFound,
}

public class ScrapeResult
{
    public ScrapeStatus Status     { get; init; }
    /// <summary>The freshly fetched (proposed) metadata. Null for <see cref="ScrapeStatus.NoApiKey"/> and <see cref="ScrapeStatus.NotFound"/>.</summary>
    public MangaMetadata? Data     { get; init; }
    /// <summary>The previously stored metadata. Only populated when <see cref="Status"/> is <see cref="ScrapeStatus.Conflict"/>.</summary>
    public MangaMetadata? Existing { get; init; }
    /// <summary>User-facing explanation. Always set for <see cref="ScrapeStatus.NoApiKey"/> and <see cref="ScrapeStatus.NotFound"/>.</summary>
    public string? Message         { get; init; }
}
