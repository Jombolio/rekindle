using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
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

    /// <summary>Returns stored metadata for a manga media item. 404 if none scraped yet.</summary>
    [HttpGet("{mediaId}")]
    public async Task<IActionResult> GetMetadata(string mediaId)
    {
        var meta = await metadataRepo.GetAsync(mediaId);
        if (meta is null) return NotFound();
        return Ok(meta);
    }

    // ── Admin-only scrape ────────────────────────────────────────────────────

    /// <summary>Triggers a fresh metadata scrape for a manga or comic folder media item.</summary>
    [HttpPost("{mediaId}/scrape")]
    [Authorize(Policy = PermissionPolicies.IsAdmin)]
    public async Task<IActionResult> Scrape(string mediaId)
    {
        var media = await mediaRepo.GetByIdAsync(mediaId);
        if (media is null) return NotFound(new { error = "Media item not found." });
        if (media.MediaType != "folder")
            return BadRequest(new { error = "Metadata scraping is only supported for folder media." });

        var library = await libraryRepo.GetByIdAsync(media.LibraryId);
        var libraryType = library?.Type ?? "comic";

        var malClientId     = await metadataRepo.GetConfigAsync("mal_client_id");
        var comicVineApiKey = await metadataRepo.GetConfigAsync("comicvine_api_key");
        var meta = await scraper.ScrapeAsync(media, libraryType, malClientId, comicVineApiKey);

        if (meta is null)
            return NotFound(new { error = "No metadata found for this title on any configured source." });

        return Ok(meta);
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
            malClientIdSet       = config.ContainsKey("mal_client_id") &&
                                   !string.IsNullOrWhiteSpace(config["mal_client_id"]),
            comicvineApiKeySet   = config.ContainsKey("comicvine_api_key") &&
                                   !string.IsNullOrWhiteSpace(config["comicvine_api_key"]),
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
