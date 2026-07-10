using Dapper;
using Rekindle.Core.Database;
using Rekindle.Core.Models;

namespace Rekindle.Core.Repositories;

public class ProgressRepository(DbConnectionFactory factory)
{
    public async Task<ReadingProgress?> GetAsync(string userId, string mediaId)
    {
        using var conn = factory.Create();
        var row = await conn.QuerySingleOrDefaultAsync<ReadingProgress>(
            """
            SELECT user_id AS UserId, media_id AS MediaId, current_page AS CurrentPage,
                   is_completed AS IsCompleted, last_read_at AS LastReadAt
            FROM reading_progress
            WHERE user_id = @userId AND media_id = @mediaId;
            """,
            new { userId, mediaId });
        return row is null ? null : NormalizeUtc(row);
    }

    public async Task<IEnumerable<ReadingProgress>> GetAllForUserAsync(string userId)
    {
        using var conn = factory.Create();
        var rows = await conn.QueryAsync<ReadingProgress>(
            """
            SELECT user_id AS UserId, media_id AS MediaId, current_page AS CurrentPage,
                   is_completed AS IsCompleted, last_read_at AS LastReadAt
            FROM reading_progress
            WHERE user_id = @userId
            ORDER BY last_read_at DESC;
            """,
            new { userId });
        return rows.Select(NormalizeUtc);
    }

    // SQLite stores last_read_at as offset-less TEXT, so Dapper materialises it
    // with Kind=Unspecified and JSON serialisation would emit it without the 'Z'
    // suffix — which ISO-8601 consumers then parse as LOCAL time. The column is
    // always written from UTC values; restore that fact on the way out.
    private static ReadingProgress NormalizeUtc(ReadingProgress row)
    {
        row.LastReadAt = DateTime.SpecifyKind(row.LastReadAt, DateTimeKind.Utc);
        return row;
    }

    /// <param name="trustClientOrdering">
    /// True when the write carries a client-supplied timestamp. Those writes are
    /// applied verbatim (newest-timestamp-wins via the WHERE guard), so backward
    /// navigation persists and a stale offline-queued flush is rejected outright.
    /// Legacy writes (no client timestamp) get an arrival-time stamp that always
    /// passes the guard, so they keep the high-water-mark clamp as protection
    /// against open-time page-0 races from older clients.
    /// </param>
    public async Task UpsertAsync(ReadingProgress progress, bool trustClientOrdering = false)
    {
        var currentPageExpr = trustClientOrdering
            ? "excluded.current_page"
            : """
              CASE
                  -- Re-reading a finished book: the client restarts at 0, so take
                  -- the new (lower) resume position instead of the high-water mark,
                  -- otherwise page and is_completed desync (page stuck at the end).
                  WHEN reading_progress.is_completed = 1 AND excluded.is_completed = 0
                      THEN excluded.current_page
                  ELSE MAX(current_page, excluded.current_page)
              END
              """;

        using var conn = factory.Create();
        await conn.ExecuteAsync(
            $"""
            INSERT INTO reading_progress (user_id, media_id, current_page, is_completed, last_read_at)
            VALUES (@UserId, @MediaId, @CurrentPage, @IsCompleted, @LastReadAt)
            ON CONFLICT(user_id, media_id) DO UPDATE SET
                current_page = {currentPageExpr},
                is_completed = excluded.is_completed,
                last_read_at = excluded.last_read_at
            WHERE excluded.last_read_at >= reading_progress.last_read_at;
            """, progress);
    }
}
