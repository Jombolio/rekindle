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
    /// Scrapes metadata for a media item using the appropriate source
    /// based on <paramref name="libraryType"/>:
    /// "comic" → ComicVine (if key set), fallback none.
    /// "manga" → MAL (if key set) then AniList.
    /// Other  → MAL (if key set) then AniList then ComicVine (if key set).
    /// </summary>
    public async Task<MangaMetadata?> ScrapeAsync(
        Media media,
        string libraryType,
        string? malClientId,
        string? comicVineApiKey,
        CancellationToken ct = default)
    {
        var searchTitle = media.Series ?? media.Title;
        logger.LogInformation("Scraping metadata for '{Title}' (library type: {Type})", searchTitle, libraryType);

        var isComic = libraryType.Equals("comic", StringComparison.OrdinalIgnoreCase);
        var isManga = libraryType.Equals("manga", StringComparison.OrdinalIgnoreCase);

        // ── Comics ───────────────────────────────────────────────────────────
        if (isComic)
        {
            if (string.IsNullOrWhiteSpace(comicVineApiKey))
            {
                logger.LogWarning("No ComicVine API key configured — cannot scrape comic metadata.");
                return null;
            }
            var cvResult = await comicVine.SearchVolumeAsync(searchTitle, comicVineApiKey, ct);
            if (cvResult is not null)
            {
                var meta = new MangaMetadata
                {
                    MediaId       = media.Id,
                    Title         = cvResult.Title,
                    Synopsis      = cvResult.Synopsis,
                    Genres        = cvResult.Publisher,
                    Year          = cvResult.Year,
                    ComicvineId   = cvResult.ComicvineId,
                    Source        = "comicvine",
                    LastScrapedAt = DateTime.UtcNow,
                };
                await repo.UpsertAsync(meta);
                return meta;
            }
            logger.LogWarning("No ComicVine result for '{Title}'", searchTitle);
            return null;
        }

        // ── Manga & fallback ─────────────────────────────────────────────────

        // Try MAL first when a client ID is available
        if (!string.IsNullOrWhiteSpace(malClientId))
        {
            var malResult = await mal.SearchAsync(searchTitle, malClientId, ct);
            if (malResult is not null)
            {
                var meta = new MangaMetadata
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
                await repo.UpsertAsync(meta);
                return meta;
            }
        }

        // Fall back to AniList (no API key required)
        var aniResult = await aniList.SearchAsync(searchTitle, ct);
        if (aniResult is not null)
        {
            var meta = new MangaMetadata
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
            await repo.UpsertAsync(meta);
            return meta;
        }

        logger.LogWarning("No metadata found for '{Title}'", searchTitle);
        return null;
    }
}
