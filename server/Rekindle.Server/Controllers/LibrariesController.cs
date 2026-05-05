using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Rekindle.Server.Authorization;
using Rekindle.Core.Models;
using Rekindle.Core.Repositories;
using Rekindle.Core.Services;

namespace Rekindle.Server.Controllers;

[ApiController]
[Route("api/libraries")]
[Authorize]
public class LibrariesController(
    LibraryRepository libraryRepository,
    LibraryScannerService scanner,
    ScanProgressTracker progressTracker) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> GetAll()
    {
        var libraries = await libraryRepository.GetAllAsync();
        return Ok(libraries);
    }

    [HttpGet("{id}")]
    public async Task<IActionResult> GetById(string id)
    {
        var library = await libraryRepository.GetByIdAsync(id);
        return library is null ? NotFound() : Ok(library);
    }

    [HttpPost]
    [Authorize(Policy = PermissionPolicies.IsAdmin)]
    public async Task<IActionResult> Create([FromBody] CreateLibraryRequest req)
    {
        if (string.IsNullOrWhiteSpace(req.Name) || string.IsNullOrWhiteSpace(req.RootPath))
            return BadRequest(new { error = "Name and root path are required." });

        var validTypes = new[] { "comic", "manga", "book" };
        if (!validTypes.Contains(req.Type))
            return BadRequest(new { error = "Type must be 'comic', 'manga', or 'book'." });

        try
        {
            Directory.CreateDirectory(req.RootPath);
        }
        catch (Exception ex)
        {
            return BadRequest(new { error = $"Could not create directory: {ex.Message}" });
        }

        var library = new Library
        {
            Id = Guid.NewGuid().ToString(),
            Name = req.Name,
            RootPath = req.RootPath,
            Type = req.Type
        };

        await libraryRepository.InsertAsync(library);
        return CreatedAtAction(nameof(GetById), new { id = library.Id }, library);
    }

    [HttpPut("{id}")]
    [Authorize(Policy = PermissionPolicies.IsAdmin)]
    public async Task<IActionResult> Update(string id, [FromBody] UpdateLibraryRequest req)
    {
        var library = await libraryRepository.GetByIdAsync(id);
        if (library is null) return NotFound();

        if (string.IsNullOrWhiteSpace(req.Name) || string.IsNullOrWhiteSpace(req.RootPath))
            return BadRequest(new { error = "Name and root path are required." });

        var validTypes = new[] { "comic", "manga", "book" };
        if (!validTypes.Contains(req.Type))
            return BadRequest(new { error = "Type must be 'comic', 'manga', or 'book'." });

        try
        {
            Directory.CreateDirectory(req.RootPath);
        }
        catch (Exception ex)
        {
            return BadRequest(new { error = $"Could not create directory: {ex.Message}" });
        }

        library.Name = req.Name;
        library.RootPath = req.RootPath;
        library.Type = req.Type;
        await libraryRepository.UpdateAsync(library);

        return Ok(library);
    }

    [HttpPost("{id}/scan")]
    [Authorize(Policy = PermissionPolicies.CanManageMedia)]
    public async Task<IActionResult> Scan(string id)
    {
        var library = await libraryRepository.GetByIdAsync(id);
        if (library is null)
            return NotFound();

        // Fire-and-forget — scan runs in background
        _ = Task.Run(() => scanner.ScanAsync(library));

        return Accepted(new { message = "Scan started." });
    }

    [HttpGet("{id}/scan/progress")]
    public async Task<IActionResult> GetScanProgress(string id)
    {
        var library = await libraryRepository.GetByIdAsync(id);
        if (library is null)
            return NotFound();

        var p = progressTracker.Get(id);
        if (p is null)
            return Ok(new
            {
                phase = "idle",
                filesTotal = 0,
                filesProcessed = 0,
                added = 0,
                removed = 0,
                folders = 0,
                coversQueued = 0,
                coversGenerated = 0,
            });

        return Ok(new
        {
            phase           = p.Phase,
            filesTotal      = p.FilesTotal,
            filesProcessed  = p.FilesProcessed,
            added           = p.Added,
            removed         = p.Removed,
            folders         = p.Folders,
            coversQueued    = p.CoversQueued,
            coversGenerated = p.CoversGenerated,
            startedAt       = p.StartedAt,
            completedAt     = p.CompletedAt,
        });
    }

    [HttpDelete("{id}")]
    [Authorize(Policy = PermissionPolicies.IsAdmin)]
    public async Task<IActionResult> Delete(string id)
    {
        var library = await libraryRepository.GetByIdAsync(id);
        if (library is null)
            return NotFound();

        await libraryRepository.DeleteAsync(id);
        return NoContent();
    }

    public record CreateLibraryRequest(string Name, string RootPath, string Type);
    public record UpdateLibraryRequest(string Name, string RootPath, string Type);
}
