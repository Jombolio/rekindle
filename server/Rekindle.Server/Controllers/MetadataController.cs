using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Rekindle.Core.Models;
using Rekindle.Core.Repositories;
using Rekindle.Core.Services;
using Rekindle.Server.Authorization;

namespace Rekindle.Server.Controllers;

[ApiController]
[Route("api/metadata")]
[Authorize]
public class MetadataController(
    MetadataRepository metadataRepo,
    MediaRepository mediaRepo,
    LibraryRepository libraryRepo,
    MetadataScraperService scraper) : ControllerBase
{
    // ── Public read ──────────────────────────────────────────────────────────

    [HttpGet("{mediaId}")]
    public async Task<IActionResult> GetMetadata(string mediaId)
    {
        var meta = await metadataRepo.GetAsync(mediaId);
        if (meta is null) return NotFound();
        return Ok(meta);
    }

    // ── Admin scrape ─────────────────────────────────────────────────────────

    /// <summary>
    /// Fetches fresh metadata and compares it with any stored entry.
    /// Returns one of three shapes:
    ///   { status: "created",   data: {...} }          — new data written immediately
    ///   { status: "no_change", data: {...} }           — matches stored; no write performed
    ///   { status: "conflict",  data: {...}, existing: {...} } — differs; call /commit to save
    /// </summary>
    [HttpPost("{mediaId}/scrape")]
    [Authorize(Policy = PermissionPolicies.IsAdmin)]
    public async Task<IActionResult> Scrape(string mediaId)
    {
        var media = await mediaRepo.GetByIdAsync(mediaId);
        if (media is null) return NotFound(new { error = "Media item not found." });
        if (media.MediaType != "folder")
            return BadRequest(new { error = "Metadata scraping is only supported for folder media." });

        var library        = await libraryRepo.GetByIdAsync(media.LibraryId);
        var libraryType    = library?.Type ?? "comic";
        var malClientId    = await metadataRepo.GetConfigAsync("mal_client_id");
        var comicVineKey   = await metadataRepo.GetConfigAsync("comicvine_api_key");

        var result = await scraper.ScrapeAsync(media, libraryType, malClientId, comicVineKey);

        return result.Status switch
        {
            ScrapeStatus.NoApiKey  => UnprocessableEntity(new { error = result.Message }),
            ScrapeStatus.NotFound  => NotFound(new { error = result.Message }),
            _ => Ok(new
            {
                status   = result.Status.ToString().ToLowerInvariant(),
                data     = result.Data,
                existing = result.Existing,
            }),
        };
    }

    // ── Manual edit (level 3+) ───────────────────────────────────────────────

    /// <summary>Saves manually edited metadata, overwriting the stored entry.</summary>
    [HttpPut("{mediaId}")]
    [Authorize(Policy = PermissionPolicies.CanManageMedia)]
    public async Task<IActionResult> UpdateMetadata(string mediaId, [FromBody] MangaMetadata metadata)
    {
        if (metadata.MediaId != mediaId)
            return BadRequest(new { error = "mediaId in body does not match the route." });

        metadata.LastScrapedAt = DateTime.UtcNow;
        await metadataRepo.UpsertAsync(metadata);
        return Ok(metadata);
    }

    // ── Admin commit ─────────────────────────────────────────────────────────

    /// <summary>
    /// Persists the supplied metadata record, overwriting any existing entry.
    /// Called by the admin after reviewing a conflict returned by /scrape.
    /// The client sends either the proposed data or the existing data unchanged.
    /// </summary>
    [HttpPost("{mediaId}/commit")]
    [Authorize(Policy = PermissionPolicies.IsAdmin)]
    public async Task<IActionResult> Commit(string mediaId, [FromBody] MangaMetadata metadata)
    {
        if (metadata.MediaId != mediaId)
            return BadRequest(new { error = "mediaId in body does not match the route." });

        metadata.LastScrapedAt = DateTime.UtcNow;
        await metadataRepo.UpsertAsync(metadata);
        return Ok(metadata);
    }
}

// ── Admin config ─────────────────────────────────────────────────────────────

[ApiController]
[Route("api/admin/metadata")]
[Authorize(Policy = PermissionPolicies.IsAdmin)]
public class MetadataAdminController(MetadataRepository metadataRepo) : ControllerBase
{
    [HttpGet("config")]
    public async Task<IActionResult> GetConfig()
    {
        var config = await metadataRepo.GetAllConfigAsync();
        return Ok(new
        {
            malClientIdSet     = config.ContainsKey("mal_client_id")     && !string.IsNullOrWhiteSpace(config["mal_client_id"]),
            comicvineApiKeySet = config.ContainsKey("comicvine_api_key") && !string.IsNullOrWhiteSpace(config["comicvine_api_key"]),
        });
    }

    [HttpPut("config")]
    public async Task<IActionResult> SetConfig([FromBody] MetadataConfigRequest request)
    {
        if (!string.IsNullOrWhiteSpace(request.MalClientId))
            await metadataRepo.SetConfigAsync("mal_client_id", request.MalClientId.Trim());

        if (!string.IsNullOrWhiteSpace(request.ComicvineApiKey))
            await metadataRepo.SetConfigAsync("comicvine_api_key", request.ComicvineApiKey.Trim());

        return Ok(new { message = "Configuration saved." });
    }
}

public record MetadataConfigRequest(string? MalClientId, string? ComicvineApiKey = null);
