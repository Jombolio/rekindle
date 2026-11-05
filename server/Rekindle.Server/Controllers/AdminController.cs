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
    IOptions<RekindleOptions> options,
    ILogger<AdminController> logger) : ControllerBase
{
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

    // ── Cache ────────────────────────────────────────────────────────────────

    [HttpDelete("cache")]
    public IActionResult ClearCache()
    {
        var pagesCache = Path.Combine(options.Value.CachePath, "pages");
        var booksCache = new DirectoryInfo(Path.Combine(options.Value.CachePath, "books"));
        if (!Directory.Exists(pagesCache) && !booksCache.Exists)
            return Ok(new { message = "Cache is already empty." });

        long freed = 0;
        if (Directory.Exists(pagesCache))
        {
            foreach (var dir in new DirectoryInfo(pagesCache).GetDirectories())
            {
                freed += dir.EnumerateFiles("*", SearchOption.AllDirectories).Sum(f => f.Length);
                dir.Delete(recursive: true);
            }
        }
        // Books converted from MOBI; regenerated the next time one is opened.
        if (booksCache.Exists)
        {
            foreach (var file in booksCache.GetFiles())
            {
                try
                {
                    var length = file.Length;
                    file.Delete();
                    freed += length;
                }
                catch (IOException)
                {
                    // Being served right now; it stays until the next clear.
                }
            }
        }

        logger.LogInformation("Admin cleared page cache ({FreedBytes} bytes freed)", freed);
        return Ok(new { message = "Cache cleared.", freedBytes = freed });
    }
}

// ── Upload — accessible to level 3+ (CanManageMedia) ─────────────────────────

[ApiController]
[Route("api/admin")]
[Authorize(Policy = PermissionPolicies.CanManageMedia)]
public class UploadController(
    LibraryRepository libraryRepository,
    MediaRepository mediaRepository,
    LibraryScannerService scanner,
    ScanProgressTracker progressTracker,
    ILogger<UploadController> logger) : ControllerBase
{
    private static readonly HashSet<string> AllowedExtensions =
        LibraryScannerService.SupportedExtensions;

    /// Says whether a book on the caller's machine can be imported, from just the
    /// start of the file, so nothing that can't be read is ever uploaded. [title]
    /// and [author] are the client's reading of an EPUB, which it sends no head for.
    [HttpPost("upload/inspect")]
    [RequestSizeLimit(BookImportInspector.MaxHeadBytes + 64 * 1024)]
    [RequestFormLimits(MultipartBodyLengthLimit = BookImportInspector.MaxHeadBytes + 64 * 1024)]
    public async Task<IActionResult> Inspect(
        [FromForm] string libraryId,
        [FromForm] string fileName,
        [FromForm] string? title,
        [FromForm] string? author,
        IFormFile? head)
    {
        var library = await libraryRepository.GetByIdAsync(libraryId);
        if (library is null)
            return NotFound(new { error = "Library not found." });

        var safeName = Path.GetFileName(fileName);
        if (string.IsNullOrWhiteSpace(safeName))
            return BadRequest(new { error = "Invalid file name." });

        byte[] headBytes = [];
        if (head is not null)
        {
            using var buffer = new MemoryStream();
            await head.CopyToAsync(buffer);
            headBytes = buffer.ToArray();
        }

        var existing = await mediaRepository.GetBookNamesForLibraryAsync(library.Id);
        var inspection = BookImportInspector.Inspect(safeName, headBytes, title, author, existing);
        return Ok(new
        {
            status = inspection.Status.ToString(),
            title = inspection.Title,
            author = inspection.Author,
            reason = inspection.Reason,
        });
    }

    [HttpPost("upload")]
    [RequestSizeLimit(4_294_967_296)]
    [RequestFormLimits(MultipartBodyLengthLimit = 4_294_967_296)]
    public async Task<IActionResult> Upload(
        [FromForm] string libraryId,
        [FromForm] string? relativePath,
        IFormFile? file,
        [FromForm] bool deferScan = false)
    {
        if (file is null || file.Length == 0)
            return BadRequest(new { error = "No file provided." });

        var library = await libraryRepository.GetByIdAsync(libraryId);
        if (library is null)
            return NotFound(new { error = "Library not found." });

        if (!Directory.Exists(library.RootPath))
            return BadRequest(new { error = "Library root path does not exist on the server." });

        var ext = Path.GetExtension(file.FileName).ToLowerInvariant();
        if (!AllowedExtensions.Contains(ext))
            return BadRequest(new { error = $"Unsupported file type '{ext}'. Allowed: {string.Join(", ", AllowedExtensions)}" });

        var safeName = Path.GetFileName(file.FileName);
        if (string.IsNullOrWhiteSpace(safeName))
            return BadRequest(new { error = "Invalid file name." });

        string destDir;
        if (!string.IsNullOrWhiteSpace(relativePath))
        {
            var normRel = relativePath.Replace('\\', '/').Trim('/').Trim();
            if (string.IsNullOrEmpty(normRel))
            {
                destDir = library.RootPath;
            }
            else
            {
                var libraryRoot = Path.GetFullPath(library.RootPath.TrimEnd('/', '\\'));
                var resolved    = Path.GetFullPath(Path.Combine(libraryRoot, normRel));

                if (!resolved.StartsWith(libraryRoot + Path.DirectorySeparatorChar,
                        StringComparison.OrdinalIgnoreCase)
                    && !resolved.Equals(libraryRoot, StringComparison.OrdinalIgnoreCase))
                {
                    // Log the absolute paths for diagnostics, but don't echo the
                    // server's filesystem layout back to the caller.
                    logger.LogWarning(
                        "Upload path escape attempt: normRel={NormRel} resolved={Resolved} libraryRoot={LibraryRoot}",
                        normRel, resolved, libraryRoot);
                    return BadRequest(new { error = $"Relative path '{normRel}' resolves outside the library root." });
                }

                Directory.CreateDirectory(resolved);
                destDir = resolved;
            }
        }
        else
        {
            destDir = library.RootPath;
        }

        var destPath = Path.Combine(destDir, safeName);
        if (System.IO.File.Exists(destPath))
            return Conflict(new { error = $"'{safeName}' already exists in the target location." });

        try
        {
            await using var stream = System.IO.File.Create(destPath);
            await file.CopyToAsync(stream);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to write uploaded file to {DestPath}", destPath);
            // A partial file would be scanned as a book and block a retry.
            try { System.IO.File.Delete(destPath); } catch (IOException) { }
            return StatusCode(500, new { error = "Failed to save the file on the server." });
        }

        logger.LogInformation("Uploaded '{FileName}' to library {LibraryId} at '{RelPath}'",
            safeName, libraryId, relativePath ?? "root");

        // A batch asks for one scan itself once all of its files are there.
        if (deferScan)
            return Ok(new { message = "Upload complete.", fileName = safeName });

        // Only kick off a scan if one isn't already running for this library —
        // rapid successive uploads must not race concurrent scans.
        if (progressTracker.TryBeginScan(libraryId))
        {
            _ = Task.Run(async () =>
            {
                try { await scanner.ScanAsync(library); }
                finally { progressTracker.ReleaseScan(libraryId); }
            });
        }

        return Ok(new { message = "Upload complete. Library scan started.", fileName = safeName });
    }
}
