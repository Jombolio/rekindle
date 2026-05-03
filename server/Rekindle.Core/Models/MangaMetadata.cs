namespace Rekindle.Core.Models;

public class MangaMetadata
{
    public string MediaId { get; set; } = string.Empty;
    public string? Title { get; set; }
    public string? Synopsis { get; set; }
    /// <summary>Comma-separated list of genres.</summary>
    public string? Genres { get; set; }
    public double? Score { get; set; }
    public string? Status { get; set; }
    public int? Year { get; set; }
    public int? MalId { get; set; }
    public int? AnilistId { get; set; }
    public int? ComicvineId { get; set; }
    /// <summary>"mal" | "anilist" | "comicvine"</summary>
    public string? Source { get; set; }
    public DateTime? LastScrapedAt { get; set; }
}
