using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using Rekindle.Server.Authorization;
using Rekindle.Core.Models;
using Rekindle.Core.Repositories;
using Rekindle.Core.Services;

namespace Rekindle.Server.Controllers;

[ApiController]
[Route("api/media")]
[Authorize]
public class MediaController(
    MediaRepository mediaRepository,
    ProgressRepository progressRepository,
    ArchiveService archiveService,
    IOptions<RekindleOptions> options) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> GetPaged(
        [FromQuery] string libraryId,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        if (string.IsNullOrWhiteSpace(libraryId))
            return BadRequest(new { error = "libraryId is required." });

        pageSize = Math.Clamp(pageSize, 1, 200);
        page = Math.Max(1, page);

        var (items, total) = await mediaRepository.GetPagedAsync(libraryId, page, pageSize);

        return Ok(new
        {
            items,
            total,
            page,
            pageSize,
            totalPages = (int)Math.Ceiling(total / (double)pageSize)
        });
    }

    /// Searches folders (directories/subdirectories) by title across a library.
    /// Archives and individual chapters are never returned.
    [HttpGet("search")]
    public async Task<IActionResult> Search(
        [FromQuery] string libraryId,
        [FromQuery] string q)
    {
        if (string.IsNullOrWhiteSpace(libraryId) || string.IsNullOrWhiteSpace(q))
            return BadRequest(new { error = "libraryId and q are required." });

        var folders = await mediaRepository.SearchFoldersAsync(libraryId, q.Trim());
        return Ok(folders);
    }

    [HttpGet("{id}")]
    public async Task<IActionResult> GetById(string id)
    {
        var media = await mediaRepository.GetByIdAsync(id);
        return media is null ? NotFound() : Ok(media);
    }

    [HttpGet("{id}/pagecount")]
    public async Task<IActionResult> GetPageCount(string id)
    {
        var media = await mediaRepository.GetByIdAsync(id);
        if (media is null) return NotFound();

        var count = await archiveService.GetPageCountAsync(media.Id, media.FilePath);
        var spreads = await archiveService.GetSpreadsAsync(media.Id, media.FilePath);

        if (media.PageCount != count)
            await mediaRepository.UpdatePageCountAsync(media.Id, count);

        return Ok(new { pageCount = count, spreads });
    }

    [HttpGet("{id}/chapters")]
    public async Task<IActionResult> GetChapters(string id)
    {
        var media = await mediaRepository.GetByIdAsync(id);
        if (media is null) return NotFound();
        if (media.MediaType != "folder")
            return BadRequest(new { error = "Media is not a folder." });

        var chapters = await mediaRepository.GetChaptersAsync(id);
        return Ok(chapters);
    }

    [HttpGet("{id}/cover")]
    public async Task<IActionResult> GetCover(string id)
    {
        var media = await mediaRepository.GetByIdAsync(id);
        if (media is null)
            return NotFound();

        if (media.CoverCachePath is not null)
        {
            var coverPath = Path.IsPathRooted(media.CoverCachePath)
                ? media.CoverCachePath
                : Path.GetFullPath(media.CoverCachePath, options.Value.CachePath);
            if (System.IO.File.Exists(coverPath))
                return PhysicalFile(coverPath, "image/jpeg");
        }

        // Cover not yet generated — stream first image directly
        var stream = await archiveService.OpenCoverStreamAsync(media.FilePath);
        if (stream is null)
            return NotFound(new { error = "No cover image available." });

        return File(stream, "image/jpeg");
    }

    [HttpGet("{id}/page/{pageNum:int}")]
    public async Task<IActionResult> GetPage(string id, int pageNum)
    {
        var media = await mediaRepository.GetByIdAsync(id);
        if (media is null)
            return NotFound();

        var pagePath = await archiveService.GetPagePathAsync(media.Id, media.FilePath, pageNum);
        if (pagePath is null)
            return NotFound(new { error = "Page not found." });

        // Update page count in DB on first extraction
        if (media.PageCount is null)
        {
            var count = await archiveService.GetPageCountAsync(media.Id, media.FilePath);
            await mediaRepository.UpdatePageCountAsync(media.Id, count);
        }

        var mimeType = GetImageMimeType(pagePath);
        return PhysicalFile(pagePath, mimeType);
    }

    [HttpGet("{id}/download")]
    [Authorize(Policy = PermissionPolicies.CanDownload)]
    public async Task<IActionResult> Download(string id)
    {
        var media = await mediaRepository.GetByIdAsync(id);
        if (media is null)
            return NotFound();

        if (!System.IO.File.Exists(media.FilePath))
            return NotFound(new { error = "File not found on server." });

        var mimeType = GetArchiveMimeType(media.Format);
        var fileName = Path.GetFileName(media.FilePath);

        return PhysicalFile(media.FilePath, mimeType, fileName, enableRangeProcessing: true);
    }

    [HttpPost("{id}/progress")]
    public async Task<IActionResult> UpdateProgress(string id, [FromBody] UpdateProgressRequest req)
    {
        var media = await mediaRepository.GetByIdAsync(id);
        if (media is null)
            return NotFound();

        var userId = GetUserId();
        if (userId is null)
            return Unauthorized();

        var progress = new ReadingProgress
        {
            UserId = userId,
            MediaId = id,
            CurrentPage = Math.Max(0, req.CurrentPage),
            IsCompleted = req.IsCompleted,
            LastReadAt = DateTime.UtcNow
        };

        await progressRepository.UpsertAsync(progress);
        return Ok(progress);
    }

    [HttpGet("{id}/progress")]
    public async Task<IActionResult> GetProgress(string id)
    {
        var userId = GetUserId();
        if (userId is null)
            return Unauthorized();

        var progress = await progressRepository.GetAsync(userId, id);
        return progress is null ? Ok(new { currentPage = 0, isCompleted = false }) : Ok(progress);
    }

    private string? GetUserId() =>
        User.FindFirstValue(ClaimTypes.NameIdentifier)
        ?? User.FindFirstValue(System.IdentityModel.Tokens.Jwt.JwtRegisteredClaimNames.Sub);

    private static string GetImageMimeType(string path) => Path.GetExtension(path).ToLowerInvariant() switch
    {
        ".png" => "image/png",
        ".webp" => "image/webp",
        ".gif" => "image/gif",
        _ => "image/jpeg"
    };

    private static string GetArchiveMimeType(string format) => format.ToLowerInvariant() switch
    {
        "epub" => "application/epub+zip",
        "pdf" => "application/pdf",
        "mobi" => "application/x-mobipocket-ebook",
        _ => "application/octet-stream"
    };

    public record UpdateProgressRequest(int CurrentPage, bool IsCompleted);
}
