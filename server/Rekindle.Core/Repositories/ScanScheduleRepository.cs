using Dapper;
using Rekindle.Core.Database;
using Rekindle.Core.Models;

namespace Rekindle.Core.Repositories;

/// <summary>
/// Scheduled scans, one per library at most. Deleting a library deletes its
/// schedule with it.
/// </summary>
public class ScanScheduleRepository(DbConnectionFactory factory)
{
    private const string Columns =
        "library_id AS LibraryId, interval_hours AS IntervalHours, " +
        "last_run_at AS LastRunAt, next_run_at AS NextRunAt";

    public async Task<IReadOnlyList<ScanSchedule>> GetAllAsync()
    {
        using var conn = factory.Create();
        var rows = await conn.QueryAsync<ScanSchedule>($"SELECT {Columns} FROM library_scan_schedules;");
        return rows.Select(AsUtc).ToList();
    }

    public async Task<ScanSchedule?> GetAsync(string libraryId)
    {
        using var conn = factory.Create();
        var row = await conn.QuerySingleOrDefaultAsync<ScanSchedule>(
            $"SELECT {Columns} FROM library_scan_schedules WHERE library_id = @libraryId;",
            new { libraryId });
        return row is null ? null : AsUtc(row);
    }

    /// <summary>Sets a library's interval and next run, keeping when it last ran.</summary>
    public async Task UpsertAsync(string libraryId, int intervalHours, DateTime nextRunAt)
    {
        using var conn = factory.Create();
        await conn.ExecuteAsync(
            """
            INSERT INTO library_scan_schedules (library_id, interval_hours, next_run_at)
            VALUES (@libraryId, @intervalHours, @nextRunAt)
            ON CONFLICT(library_id) DO UPDATE SET
                interval_hours = excluded.interval_hours,
                next_run_at = excluded.next_run_at;
            """,
            new { libraryId, intervalHours, nextRunAt });
    }

    public async Task RecordRunAsync(string libraryId, DateTime ranAt, DateTime nextRunAt)
    {
        using var conn = factory.Create();
        await conn.ExecuteAsync(
            "UPDATE library_scan_schedules SET last_run_at = @ranAt, next_run_at = @nextRunAt WHERE library_id = @libraryId;",
            new { libraryId, ranAt, nextRunAt });
    }

    public async Task DeleteAsync(string libraryId)
    {
        using var conn = factory.Create();
        await conn.ExecuteAsync(
            "DELETE FROM library_scan_schedules WHERE library_id = @libraryId;", new { libraryId });
    }

    // SQLite keeps no time zone, and every time here is written in UTC.
    private static ScanSchedule AsUtc(ScanSchedule s)
    {
        s.NextRunAt = DateTime.SpecifyKind(s.NextRunAt, DateTimeKind.Utc);
        if (s.LastRunAt is { } last) s.LastRunAt = DateTime.SpecifyKind(last, DateTimeKind.Utc);
        return s;
    }
}
