using System.Data;
using Dapper;
using Rekindle.Core.Database;
using Rekindle.Core.Models;
using Rekindle.Core.Utilities;

namespace Rekindle.Core.Repositories;

public class MediaRepository(DbConnectionFactory factory)
{
    private const string SelectColumns = """
        id, library_id AS LibraryId, title, series, volume, file_path AS FilePath,
        format, page_count AS PageCount, cover_cache_path AS CoverCachePath,
        media_type AS MediaType, relative_path AS RelativePath,
        parent_id AS ParentId, added_at AS AddedAt
        """;

    /// Returns top-level media only (no chapter children), natural-sorted.
    public async Task<(IEnumerable<Media> Items, int Total)> GetPagedAsync(string libraryId, int page, int pageSize)
    {
        using var conn = factory.Create();

        // Fetch all top-level items so natural sort can work across the full
        // dataset before slicing into pages.
        var all = await conn.QueryAsync<Media>(
            $"""
            SELECT {SelectColumns}
            FROM media
            WHERE library_id = @libraryId AND parent_id IS NULL;
            """,
            new { libraryId });

        var nc = NaturalStringComparer.Instance;
        var sorted = all
            .OrderBy(m => m.Series, nc)
            .ThenBy(m => m.Volume)
            .ThenBy(m => m.Title, nc)
            .ToList();

        var offset = (page - 1) * pageSize;
        return (sorted.Skip(offset).Take(pageSize), sorted.Count);
    }

    public async Task<Media?> GetByIdAsync(string id)
    {
        using var conn = factory.Create();
        return await conn.QuerySingleOrDefaultAsync<Media>(
            $"SELECT {SelectColumns} FROM media WHERE id = @id;",
            new { id });
    }

    /// Returns all folders in a library whose title contains [query] (case-insensitive),
    /// at any nesting depth. Archives are excluded — mediaType must be "folder".
    public async Task<IEnumerable<Media>> SearchFoldersAsync(string libraryId, string query)
    {
        using var conn = factory.Create();
        var pattern = $"%{query}%";
        var rows = await conn.QueryAsync<Media>(
            $"""
            SELECT {SelectColumns}
            FROM media
            WHERE library_id = @libraryId
              AND media_type = 'folder'
              AND (title LIKE @pattern OR sort_title LIKE @pattern)
            ORDER BY relative_path;
            """,
            new { libraryId, pattern });
        return rows;
    }

    /// Returns all chapter entries for a folder, natural-sorted by file path.
    public async Task<IEnumerable<Media>> GetChaptersAsync(string parentId)
    {
        using var conn = factory.Create();
        var rows = await conn.QueryAsync<Media>(
            $"""
            SELECT {SelectColumns}
            FROM media
            WHERE parent_id = @parentId;
            """,
            new { parentId });

        return rows.OrderBy(m => m.FilePath, NaturalStringComparer.Instance);
    }

    public async Task<IEnumerable<MediaPathEntry>> GetAllPathsForLibraryAsync(string libraryId)
    {
        using var conn = factory.Create();
        var rows = await conn.QueryAsync(
            "SELECT id, file_path, media_type, parent_id FROM media WHERE library_id = @libraryId;",
            new { libraryId });
        return rows.Select(r => new MediaPathEntry(
            (string)r.id,
            (string)r.file_path,
            (string)r.media_type,
            (string?)r.parent_id));
    }

    public async Task InsertAsync(Media media)
    {
        using var conn = factory.Create();
        await conn.ExecuteAsync(
            """
            INSERT INTO media
                (id, library_id, title, series, volume, file_path, format,
                 page_count, cover_cache_path, media_type, relative_path, parent_id, added_at)
            VALUES
                (@Id, @LibraryId, @Title, @Series, @Volume, @FilePath, @Format,
                 @PageCount, @CoverCachePath, @MediaType, @RelativePath, @ParentId, @AddedAt);
            """, media);
    }

    public async Task UpdateParentAsync(string id, string? parentId)
    {
        using var conn = factory.Create();
        await conn.ExecuteAsync(
            "UPDATE media SET parent_id = @parentId WHERE id = @id;",
            new { id, parentId });
    }

    public async Task UpdateCoverAsync(string id, string coverCachePath)
    {
        using var conn = factory.Create();
        await conn.ExecuteAsync(
            "UPDATE media SET cover_cache_path = @coverCachePath WHERE id = @id;",
            new { id, coverCachePath });
    }

    public async Task UpdatePageCountAsync(string id, int pageCount)
    {
        using var conn = factory.Create();
        await conn.ExecuteAsync(
            "UPDATE media SET page_count = @pageCount WHERE id = @id;",
            new { id, pageCount });
    }

    /// Deletes by file path, recursively removing all descendants first.
    public async Task DeleteByFilePathAsync(string filePath)
    {
        using var conn = factory.Create();
        var id = await conn.ExecuteScalarAsync<string?>(
            "SELECT id FROM media WHERE file_path = @filePath;", new { filePath });
        if (id is not null)
            await DeleteDescendantsAsync(conn, id);
        await conn.ExecuteAsync("DELETE FROM media WHERE file_path = @filePath;", new { filePath });
    }

    private static async Task DeleteDescendantsAsync(IDbConnection conn, string parentId)
    {
        var children = (await conn.QueryAsync(
            "SELECT id, media_type FROM media WHERE parent_id = @parentId;",
            new { parentId })).ToList();

        foreach (var child in children)
        {
            if ((string)child.media_type == "folder")
                await DeleteDescendantsAsync(conn, (string)child.id);
        }

        await conn.ExecuteAsync(
            "DELETE FROM media WHERE parent_id = @parentId;", new { parentId });
    }

    public async Task<int> CountAsync()
    {
        using var conn = factory.Create();
        return await conn.ExecuteScalarAsync<int>("SELECT COUNT(*) FROM media;");
    }
}

public record MediaPathEntry(string Id, string FilePath, string MediaType, string? ParentId);
