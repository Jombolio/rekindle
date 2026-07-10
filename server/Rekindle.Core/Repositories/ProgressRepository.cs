using Dapper;
using Rekindle.Core.Database;
using Rekindle.Core.Models;

namespace Rekindle.Core.Repositories;

public class ProgressRepository(DbConnectionFactory factory)
{
    public async Task<ReadingProgress?> GetAsync(string userId, string mediaId)
    {
        using var conn = factory.Create();
        return await conn.QuerySingleOrDefaultAsync<ReadingProgress>(
            """
            SELECT user_id AS UserId, media_id AS MediaId, current_page AS CurrentPage,
                   is_completed AS IsCompleted, last_read_at AS LastReadAt
            FROM reading_progress
            WHERE user_id = @userId AND media_id = @mediaId;
            """,
            new { userId, mediaId });
    }

    public async Task<IEnumerable<ReadingProgress>> GetAllForUserAsync(string userId)
    {
        using var conn = factory.Create();
        return await conn.QueryAsync<ReadingProgress>(
            """
            SELECT user_id AS UserId, media_id AS MediaId, current_page AS CurrentPage,
                   is_completed AS IsCompleted, last_read_at AS LastReadAt
            FROM reading_progress
            WHERE user_id = @userId
            ORDER BY last_read_at DESC;
            """,
            new { userId });
    }

    public async Task UpsertAsync(ReadingProgress progress)
    {
        using var conn = factory.Create();
        await conn.ExecuteAsync(
            """
            INSERT INTO reading_progress (user_id, media_id, current_page, is_completed, last_read_at)
            VALUES (@UserId, @MediaId, @CurrentPage, @IsCompleted, @LastReadAt)
            ON CONFLICT(user_id, media_id) DO UPDATE SET
                current_page = CASE
                    -- Re-reading a finished book: the client restarts at 0, so take
                    -- the new (lower) resume position instead of the high-water mark,
                    -- otherwise page and is_completed desync (page stuck at the end).
                    WHEN reading_progress.is_completed = 1 AND excluded.is_completed = 0
                        THEN excluded.current_page
                    ELSE MAX(current_page, excluded.current_page)
                END,
                is_completed = excluded.is_completed,
                last_read_at = excluded.last_read_at
            WHERE excluded.last_read_at >= reading_progress.last_read_at;
            """, progress);
    }
}
