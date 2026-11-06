using Dapper;
using Rekindle.Core.Database;

namespace Rekindle.Core.Repositories;

/// <summary>
/// Archives a user has asked to leave out of their series progress, such as an
/// annual or a bundled volume they don't mean to read. An ignored archive
/// doesn't count towards a series being finished, how far through it is, or how
/// many chapters are new. Its own progress is still kept and shown.
/// </summary>
public class TrackingIgnoreRepository(DbConnectionFactory factory)
{
    public async Task<IReadOnlySet<string>> GetAllForUserAsync(string userId)
    {
        using var conn = factory.Create();
        var ids = await conn.QueryAsync<string>(
            "SELECT media_id FROM tracking_ignores WHERE user_id = @userId;", new { userId });
        return ids.ToHashSet();
    }

    public async Task IgnoreAsync(string userId, IReadOnlyCollection<string> mediaIds, DateTime at)
    {
        if (mediaIds.Count == 0) return;
        using var conn = factory.Create();
        using var tx = conn.BeginTransaction();
        await conn.ExecuteAsync(
            """
            INSERT INTO tracking_ignores (user_id, media_id, ignored_at)
            VALUES (@userId, @mediaId, @at)
            ON CONFLICT(user_id, media_id) DO NOTHING;
            """,
            mediaIds.Select(mediaId => new { userId, mediaId, at }), tx);
        tx.Commit();
    }

    public async Task TrackAsync(string userId, IReadOnlyCollection<string> mediaIds)
    {
        if (mediaIds.Count == 0) return;
        using var conn = factory.Create();
        await conn.ExecuteAsync(
            "DELETE FROM tracking_ignores WHERE user_id = @userId AND media_id IN @mediaIds;",
            new { userId, mediaIds });
    }
}
