using Dapper;
using Rekindle.Core.Database;
using Rekindle.Core.Models;

namespace Rekindle.Core.Repositories;

public class MetadataRepository(DbConnectionFactory factory)
{
    public async Task<MangaMetadata?> GetAsync(string mediaId)
    {
        using var conn = factory.Create();
        return await conn.QuerySingleOrDefaultAsync<MangaMetadata>(
            """
            SELECT media_id AS MediaId, title, synopsis, genres, score, status,
                   year, mal_id AS MalId, anilist_id AS AnilistId,
                   comicvine_id AS ComicvineId, source,
                   last_scraped_at AS LastScrapedAt
            FROM manga_metadata WHERE media_id = @mediaId;
            """,
            new { mediaId });
    }

    public async Task UpsertAsync(MangaMetadata meta)
    {
        using var conn = factory.Create();
        await conn.ExecuteAsync(
            """
            INSERT INTO manga_metadata
                (media_id, title, synopsis, genres, score, status, year,
                 mal_id, anilist_id, comicvine_id, source, last_scraped_at)
            VALUES
                (@MediaId, @Title, @Synopsis, @Genres, @Score, @Status, @Year,
                 @MalId, @AnilistId, @ComicvineId, @Source, @LastScrapedAt)
            ON CONFLICT(media_id) DO UPDATE SET
                title           = excluded.title,
                synopsis        = excluded.synopsis,
                genres          = excluded.genres,
                score           = excluded.score,
                status          = excluded.status,
                year            = excluded.year,
                mal_id          = excluded.mal_id,
                anilist_id      = excluded.anilist_id,
                comicvine_id    = excluded.comicvine_id,
                source          = excluded.source,
                last_scraped_at = excluded.last_scraped_at;
            """,
            meta);
    }

    public async Task<string?> GetConfigAsync(string key)
    {
        using var conn = factory.Create();
        return await conn.ExecuteScalarAsync<string?>(
            "SELECT value FROM metadata_config WHERE key = @key;",
            new { key });
    }

    public async Task SetConfigAsync(string key, string value)
    {
        using var conn = factory.Create();
        await conn.ExecuteAsync(
            """
            INSERT INTO metadata_config (key, value)
            VALUES (@key, @value)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value;
            """,
            new { key, value });
    }

    public async Task<Dictionary<string, string>> GetAllConfigAsync()
    {
        using var conn = factory.Create();
        var rows = await conn.QueryAsync("SELECT key, value FROM metadata_config;");
        return rows.ToDictionary(r => (string)r.key, r => (string)r.value);
    }
}
