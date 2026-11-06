using Dapper;
using Rekindle.Core.Database;

namespace Rekindle.Core.Repositories;

/// <summary>
/// Chapters a user has marked as read. A mark is kept apart from reading
/// progress: it makes a chapter count as read however far into it the user is,
/// so rereading a series or catching up doesn't unmark anything, and their place
/// in the chapter is left as it was. It stays until the user removes it.
/// </summary>
public class ReadMarkRepository(DbConnectionFactory factory)
{
    public async Task<IReadOnlySet<string>> GetAllForUserAsync(string userId)
    {
        using var conn = factory.Create();
        var ids = await conn.QueryAsync<string>(
            "SELECT media_id FROM read_marks WHERE user_id = @userId;", new { userId });
        return ids.ToHashSet();
    }

    public async Task MarkAsync(string userId, IReadOnlyCollection<string> mediaIds, DateTime markedAt)
    {
        if (mediaIds.Count == 0) return;
        using var conn = factory.Create();
        using var tx = conn.BeginTransaction();
        await conn.ExecuteAsync(
            """
            INSERT INTO read_marks (user_id, media_id, marked_at)
            VALUES (@userId, @mediaId, @markedAt)
            ON CONFLICT(user_id, media_id) DO NOTHING;
            """,
            mediaIds.Select(mediaId => new { userId, mediaId, markedAt }), tx);
        tx.Commit();
    }

    public async Task UnmarkAsync(string userId, IReadOnlyCollection<string> mediaIds)
    {
        if (mediaIds.Count == 0) return;
        using var conn = factory.Create();
        await conn.ExecuteAsync(
            "DELETE FROM read_marks WHERE user_id = @userId AND media_id IN @mediaIds;",
            new { userId, mediaIds });
    }
}
