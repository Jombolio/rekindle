using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using Rekindle.Core.Repositories;
using Rekindle.Core.Services;
using Rekindle.Server.Authorization;

namespace Rekindle.Server.Controllers;

[ApiController]
[Route("api/admin")]
[Authorize(Policy = PermissionPolicies.IsAdmin)]
public class AdminController(
    UserRepository userRepository,
    LibraryRepository libraryRepository,
    MediaRepository mediaRepository,
    LibraryScannerService scanner,
    IOptions<RekindleOptions> options,
    ILogger<AdminController> logger) : ControllerBase
{
    private static readonly HashSet<string> AllowedUploadExtensions =
        LibraryScannerService.SupportedExtensions;

    // ── Stats ────────────────────────────────────────────────────────────────

    [HttpGet("stats")]
    public async Task<IActionResult> GetStats()
    {
        var userCount = await userRepository.CountAsync();
        var libraries = (await libraryRepository.GetAllAsync()).ToList();
        var mediaCount = await mediaRepository.CountAsync();

        var pagesCache = Path.Combine(options.Value.CachePath, "pages");
        long cacheSizeBytes = 0;
        if (Directory.Exists(pagesCache))
            cacheSizeBytes = new DirectoryInfo(pagesCache)
                .EnumerateFiles("*", SearchOption.AllDirectories)
                .Sum(f => f.Length);

        return Ok(new
        {
            userCount,
            libraryCount = libraries.Count,
            mediaCount,
            cacheSizeBytes,
        });
    }

    // ── Upload ───────────────────────────────────────────────────────────────

    [HttpPost("upload")]
    [RequestSizeLimit(2_147_483_648)]          // 2 GB
    [RequestFormLimits(MultipartBodyLengthLimit = 2_147_483_648)]
    public async Task<IActionResult> Upload([FromForm] string libraryId, IFormFile? file)
    {
        if (file is null || file.Length == 0)
            return BadRequest(new { error = "No file provided." });

        var library = await libraryRepository.GetByIdAsync(libraryId);
        if (library is null)
            return NotFound(new { error = "Library not found." });

        if (!Directory.Exists(library.RootPath))
            return BadRequest(new { error = "Library root path does not exist on the server." });

        var ext = Path.GetExtension(file.FileName).ToLowerInvariant();
        if (!AllowedUploadExtensions.Contains(ext))
            return BadRequest(new { error = $"Unsupported file type '{ext}'. Allowed: {string.Join(", ", AllowedUploadExtensions)}" });

        // Path.GetFileName strips any directory components — prevents path traversal.
        var safeName = Path.GetFileName(file.FileName);
        if (string.IsNullOrWhiteSpace(safeName))
            return BadRequest(new { error = "Invalid file name." });

        var destPath = Path.Combine(library.RootPath, safeName);
        if (System.IO.File.Exists(destPath))
            return Conflict(new { error = $"'{safeName}' already exists in this library." });

        try
        {
            await using var stream = System.IO.File.Create(destPath);
            await file.CopyToAsync(stream);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to write uploaded file to {DestPath}", destPath);
            return StatusCode(500, new { error = "Failed to save the file on the server." });
        }

        _ = Task.Run(() => scanner.ScanAsync(library));

        logger.LogInformation("Admin uploaded '{FileName}' to library {LibraryId}", safeName, libraryId);
        return Ok(new { message = "Upload complete. Library scan started.", fileName = safeName });
    }

    // ── Cache ────────────────────────────────────────────────────────────────

    [HttpDelete("cache")]
    public IActionResult ClearCache()
    {
        var pagesCache = Path.Combine(options.Value.CachePath, "pages");
        if (!Directory.Exists(pagesCache))
            return Ok(new { message = "Cache is already empty." });

        long freed = 0;
        foreach (var dir in new DirectoryInfo(pagesCache).GetDirectories())
        {
            freed += dir.EnumerateFiles("*", SearchOption.AllDirectories).Sum(f => f.Length);
            dir.Delete(recursive: true);
        }

        logger.LogInformation("Admin cleared page cache ({FreedBytes} bytes freed)", freed);
        return Ok(new { message = "Cache cleared.", freedBytes = freed });
    }
}
