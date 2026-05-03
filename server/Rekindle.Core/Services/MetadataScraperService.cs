using Microsoft.Extensions.Logging;
using Rekindle.Core.Models;
using Rekindle.Core.Repositories;

namespace Rekindle.Core.Services;

public class MetadataScraperService(
    AniListService aniList,
    MalService mal,
    ComicVineService comicVine,
    MetadataRepository repo,
    ILogger<MetadataScraperService> logger)
{
    /// <summary>
    /// Fetches fresh metadata from the appropriate source, compares it with any
    /// previously stored entry, and returns a <see cref="ScrapeResult"/> indicating
    /// whether the data was created, was identical (no write needed), or conflicts
    /// with the stored version (awaiting admin confirmation before committing).
    ///
    /// Source routing is strict and exclusive:
    ///   "comic"  → ComicVine only  (MAL / AniList are never queried)
    ///   "manga"  → MAL then AniList  (ComicVine is never queried)
    ///   other    → same as "manga"
    /// </summary>
    public async Task<ScrapeResult?> ScrapeAsync(
        Media media,
        string libraryType,
        string? malClientId,
        string? comicVineApiKey,
        CancellationToken ct = default)
    {
        var searchTitle = media.Series ?? media.Title;
        logger.LogInformation("Scraping metadata for '{Title}' (library type: {Type})", searchTitle, libraryType);

        var proposed = await FetchAsync(media, libraryType, malClientId, comicVineApiKey, searchTitle, ct);
        if (proposed is null) return null;

        var existing = await repo.GetAsync(media.Id);

        // Nothing stored yet — write immediately.
        if (existing is null)
        {
            await repo.UpsertAsync(proposed);
            return new ScrapeResult { Status = ScrapeStatus.Created, Data = proposed };
        }

        // Data is identical — skip write.
        if (ContentEquals(existing, proposed))
        {
            logger.LogDebug("Metadata for '{Title}' unchanged — skipping write.", searchTitle);
            return new ScrapeResult { Status = ScrapeStatus.NoChange, Data = existing };
        }

        // Data differs — surface conflict for admin review; do not write yet.
        logger.LogInformation("Metadata conflict detected for '{Title}' — awaiting confirmation.", searchTitle);
        return new ScrapeResult { Status = ScrapeStatus.Conflict, Data = proposed, Existing = existing };
    }

    // ── Private helpers ──────────────────────────────────────────────────────

    // Source routing is a strict switch — each branch returns without falling
    // through to the other, so Comic and Manga sources remain completely isolated.
    private async Task<MangaMetadata?> FetchAsync(
        Media media,
        string libraryType,
        string? malClientId,
        string? comicVineApiKey,
        string searchTitle,
        CancellationToken ct)
    {
        if (libraryType.Equals("comic", StringComparison.OrdinalIgnoreCase))
            return await FetchComicAsync(media, comicVineApiKey, searchTitle, ct);

        // "manga" and any unrecognised type → MAL + AniList only.
        return await FetchMangaAsync(media, malClientId, searchTitle, ct);
    }

    // ── Comic: ComicVine only ────────────────────────────────────────────────

    private async Task<MangaMetadata?> FetchComicAsync(
        Media media, string? comicVineApiKey, string searchTitle, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(comicVineApiKey))
        {
            logger.LogWarning("No ComicVine API key configured — cannot scrape comic metadata.");
            return null;
        }
        var cv = await comicVine.SearchVolumeAsync(searchTitle, comicVineApiKey, ct);
        if (cv is null)
        {
            logger.LogWarning("No ComicVine result for '{Title}'", searchTitle);
            return null;
        }
        return new MangaMetadata
        {
            MediaId       = media.Id,
            Title         = cv.Title,
            Synopsis      = cv.Synopsis,
            Genres        = cv.Publisher,
            Year          = cv.Year,
            ComicvineId   = cv.ComicvineId,
            Source        = "comicvine",
            LastScrapedAt = DateTime.UtcNow,
        };
    }

    // ── Manga: MAL then AniList ──────────────────────────────────────────────

    private async Task<MangaMetadata?> FetchMangaAsync(
        Media media, string? malClientId, string searchTitle, CancellationToken ct)
    {
        if (!string.IsNullOrWhiteSpace(malClientId))
        {
            var malResult = await mal.SearchAsync(searchTitle, malClientId, ct);
            if (malResult is not null)
                return new MangaMetadata
                {
                    MediaId       = media.Id,
                    Title         = malResult.Title,
                    Synopsis      = malResult.Synopsis,
                    Genres        = string.Join(", ", malResult.Genres),
                    Score         = malResult.Score,
                    Status        = malResult.Status,
                    Year          = malResult.Year,
                    MalId         = malResult.MalId,
                    Source        = "mal",
                    LastScrapedAt = DateTime.UtcNow,
                };
        }

        var aniResult = await aniList.SearchAsync(searchTitle, ct);
        if (aniResult is not null)
            return new MangaMetadata
            {
                MediaId       = media.Id,
                Title         = aniResult.Title,
                Synopsis      = aniResult.Synopsis,
                Genres        = string.Join(", ", aniResult.Genres),
                Score         = aniResult.Score,
                Status        = aniResult.Status,
                Year          = aniResult.Year,
                AnilistId     = aniResult.AnilistId,
                Source        = "anilist",
                LastScrapedAt = DateTime.UtcNow,
            };

        logger.LogWarning("No manga metadata found for '{Title}' on MAL or AniList", searchTitle);
        return null;
    }

    /// <summary>
    /// Compares the content fields of two metadata records (timestamps excluded).
    /// Score is rounded to one decimal place to absorb trivial float drift.
    /// </summary>
    private static bool ContentEquals(MangaMetadata a, MangaMetadata b) =>
        a.Title       == b.Title       &&
        a.Synopsis    == b.Synopsis    &&
        a.Genres      == b.Genres      &&
        a.Status      == b.Status      &&
        a.Year        == b.Year        &&
        a.Source      == b.Source      &&
        a.MalId       == b.MalId       &&
        a.AnilistId   == b.AnilistId   &&
        a.ComicvineId == b.ComicvineId &&
        NullableScoreEquals(a.Score, b.Score);

    private static bool NullableScoreEquals(double? x, double? y)
    {
        if (x is null && y is null) return true;
        if (x is null || y is null) return false;
        return Math.Round(x.Value, 1) == Math.Round(y.Value, 1);
    }
}
