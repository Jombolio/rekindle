using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Rekindle.Core.Models;
using Rekindle.Core.Repositories;

namespace Rekindle.Core.Services;

/// <summary>
/// Runs scheduled library scans. Once a minute it starts any that are due, one
/// at a time so a server with several libraries isn't scanning them all at
/// once. A library already being scanned, say by someone pressing Scan, is
/// left until the next check.
/// </summary>
public sealed class ScheduledScanService(
    IServiceScopeFactory scopes,
    ScanProgressTracker progressTracker,
    TimeProvider time,
    ILogger<ScheduledScanService> logger) : BackgroundService
{
    private static readonly TimeSpan CheckEvery = TimeSpan.FromMinutes(1);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(CheckEvery, time);
        do
        {
            try
            {
                await RunDueScansAsync(stoppingToken);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                // A bad check mustn't end scheduling for good.
                logger.LogError(ex, "Checking for scheduled scans failed");
            }
        } while (await timer.WaitForNextTickAsync(stoppingToken));
    }

    /// <summary>Starts every scan that's due, one after another. Returns how many ran.</summary>
    public async Task<int> RunDueScansAsync(CancellationToken cancellationToken = default)
    {
        using var scope = scopes.CreateScope();
        var schedules = scope.ServiceProvider.GetRequiredService<ScanScheduleRepository>();
        var libraries = scope.ServiceProvider.GetRequiredService<LibraryRepository>();
        var scanner = scope.ServiceProvider.GetRequiredService<LibraryScannerService>();

        var ran = 0;
        var due = (await schedules.GetAllAsync())
            .Where(s => s.IsDue(time.GetUtcNow().UtcDateTime))
            .OrderBy(s => s.NextRunAt);
        foreach (var schedule in due)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var library = await libraries.GetByIdAsync(schedule.LibraryId);
            if (library is null) continue;
            if (!progressTracker.TryBeginScan(library.Id)) continue;

            var started = time.GetUtcNow().UtcDateTime;
            logger.LogInformation("Scheduled scan of library '{Name}'", library.Name);
            try
            {
                await scanner.ScanAsync(library);
            }
            catch (Exception ex)
            {
                // Recorded as run all the same, so a library that can't be scanned
                // waits its interval instead of being retried every minute.
                logger.LogError(ex, "Scheduled scan of library '{Name}' failed", library.Name);
            }
            finally
            {
                progressTracker.ReleaseScan(library.Id);
            }

            var finished = time.GetUtcNow().UtcDateTime;
            await schedules.RecordRunAsync(
                library.Id, started, ScanSchedule.NextAfter(started, finished, schedule.IntervalHours));
            ran++;
        }
        return ran;
    }
}
