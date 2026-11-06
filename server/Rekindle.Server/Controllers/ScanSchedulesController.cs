using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Rekindle.Core.Models;
using Rekindle.Core.Repositories;
using Rekindle.Server.Authorization;

namespace Rekindle.Server.Controllers;

/// <summary>
/// Scheduled library scans, set from the Admin Panel. Admins only: a schedule
/// keeps the server working on its own, which is a server setting rather than
/// managing media. Starting a scan by hand stays open to media managers.
/// </summary>
[ApiController]
[Route("api/admin/scan-schedules")]
[Authorize(Policy = PermissionPolicies.IsAdmin)]
public class ScanSchedulesController(
    LibraryRepository libraryRepository,
    ScanScheduleRepository scheduleRepository,
    TimeProvider time) : ControllerBase
{
    /// <summary>Every library with its schedule; an interval of 0 means none.</summary>
    [HttpGet]
    public async Task<IActionResult> GetAll()
    {
        var libraries = await libraryRepository.GetAllAsync();
        var schedules = (await scheduleRepository.GetAllAsync()).ToDictionary(s => s.LibraryId);
        return Ok(libraries
            .OrderBy(l => l.Name, StringComparer.OrdinalIgnoreCase)
            .Select(l => Describe(l, schedules.GetValueOrDefault(l.Id))));
    }

    /// <summary>Sets how often a library is scanned. An interval of 0 turns it off.</summary>
    [HttpPut("{libraryId}")]
    public async Task<IActionResult> Set(string libraryId, [FromBody] SetScanScheduleRequest req)
    {
        var library = await libraryRepository.GetByIdAsync(libraryId);
        if (library is null) return NotFound();

        if (req.IntervalHours == 0)
        {
            await scheduleRepository.DeleteAsync(libraryId);
            return Ok(Describe(library, null));
        }
        if (req.IntervalHours is < ScanSchedule.MinIntervalHours or > ScanSchedule.MaxIntervalHours)
        {
            return BadRequest(new
            {
                error = $"The interval must be 0 (off) or between {ScanSchedule.MinIntervalHours} " +
                        $"and {ScanSchedule.MaxIntervalHours} hours."
            });
        }

        var existing = await scheduleRepository.GetAsync(libraryId);
        var now = time.GetUtcNow().UtcDateTime;
        var next = existing is not null && existing.IntervalHours == req.IntervalHours
            ? existing.NextRunAt // Unchanged: keep its place.
            : ScanSchedule.FirstDue(existing?.LastRunAt, now, req.IntervalHours);
        await scheduleRepository.UpsertAsync(libraryId, req.IntervalHours, next);
        return Ok(Describe(library, await scheduleRepository.GetAsync(libraryId)));
    }

    private static object Describe(Library library, ScanSchedule? schedule) => new
    {
        libraryId = library.Id,
        libraryName = library.Name,
        intervalHours = schedule?.IntervalHours ?? 0,
        lastRunAt = schedule?.LastRunAt,
        nextRunAt = schedule?.NextRunAt,
    };

    public record SetScanScheduleRequest(int IntervalHours);
}
