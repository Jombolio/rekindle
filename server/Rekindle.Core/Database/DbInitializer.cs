using Dapper;
using Microsoft.Data.Sqlite;
using Microsoft.Extensions.Logging;

namespace Rekindle.Core.Database;

public class DbInitializer(DbConnectionFactory factory, ILogger<DbInitializer> logger)
{
    public async Task InitializeAsync()
    {
        logger.LogInformation("Initializing database...");

        using var connection = factory.Create();

        await connection.ExecuteAsync("PRAGMA journal_mode=WAL;");
        await connection.ExecuteAsync("PRAGMA foreign_keys=ON;");

        await connection.ExecuteAsync("""
            CREATE TABLE IF NOT EXISTS schema_version (
                version INTEGER PRIMARY KEY,
                applied_at DATETIME DEFAULT CURRENT_TIMESTAMP
            );
            """);

        var currentVersion = await connection.QuerySingleOrDefaultAsync<int?>(
            "SELECT MAX(version) FROM schema_version;") ?? 0;

        await ApplyMigrationsAsync(connection, currentVersion);

        logger.LogInformation("Database ready.");
    }

    private static async Task ApplyMigrationsAsync(SqliteConnection connection, int fromVersion)
    {
        if (fromVersion < 1)
            await ApplyMigration(connection, 1, Migration_001);
        if (fromVersion < 2)
            await ApplyMigration(connection, 2, Migration_002);
        if (fromVersion < 3)
            await ApplyMigration(connection, 3, Migration_003);
        if (fromVersion < 4)
            await ApplyMigration(connection, 4, Migration_004);
        if (fromVersion < 5)
            await ApplyMigration(connection, 5, Migration_005);
        if (fromVersion < 6)
            await ApplyMigration(connection, 6, Migration_006);
        if (fromVersion < 7)
            await ApplyMigration(connection, 7, Migration_007);
    }

    private static async Task ApplyMigration(SqliteConnection connection, int version, Func<SqliteConnection, Task> migration)
    {
        using var tx = connection.BeginTransaction();
        await migration(connection);
        await connection.ExecuteAsync(
            "INSERT INTO schema_version (version) VALUES (@version);",
            new { version }, tx);
        tx.Commit();
    }

    private static async Task Migration_007(SqliteConnection connection)
    {
        await connection.ExecuteAsync(
            "ALTER TABLE manga_metadata ADD COLUMN comicvine_id INTEGER;");
    }

    private static async Task Migration_006(SqliteConnection connection)
    {
        await connection.ExecuteAsync("""
            CREATE TABLE IF NOT EXISTS manga_metadata (
                media_id        TEXT PRIMARY KEY REFERENCES media(id) ON DELETE CASCADE,
                title           TEXT,
                synopsis        TEXT,
                genres          TEXT,
                score           REAL,
                status          TEXT,
                year            INTEGER,
                mal_id          INTEGER,
                anilist_id      INTEGER,
                source          TEXT,
                last_scraped_at DATETIME
            );

            CREATE TABLE IF NOT EXISTS metadata_config (
                key   TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
            """);
    }

    private static async Task Migration_005(SqliteConnection connection)
    {
        // Introduce numeric permission levels (1=read-only, 2=download, 3=manage media, 4=admin).
        // Backfill from the legacy 'role' column: admin → 4, everyone else → 2.
        await connection.ExecuteAsync(
            "ALTER TABLE users ADD COLUMN permission_level INTEGER NOT NULL DEFAULT 2;");
        await connection.ExecuteAsync(
            "UPDATE users SET permission_level = 4 WHERE role = 'admin';");
    }

    private static async Task Migration_004(SqliteConnection connection)
    {
        // Links individual chapter archives to their parent folder entry.
        // Cascade is enforced in application code (SQLite ALTER TABLE cannot add FK constraints).
        await connection.ExecuteAsync(
            "ALTER TABLE media ADD COLUMN parent_id TEXT;");
    }

    private static async Task Migration_003(SqliteConnection connection)
    {
        // Server-relative path used by clients to mirror directory structure when downloading
        await connection.ExecuteAsync(
            "ALTER TABLE media ADD COLUMN relative_path TEXT NOT NULL DEFAULT '';");
    }

    private static async Task Migration_002(SqliteConnection connection)
    {
        // Distinguish standalone archives from directory-grouped series
        await connection.ExecuteAsync(
            "ALTER TABLE media ADD COLUMN media_type TEXT NOT NULL DEFAULT 'archive';");
    }

    private static async Task Migration_001(SqliteConnection connection)
    {
        await connection.ExecuteAsync("""
            CREATE TABLE IF NOT EXISTS users (
                id TEXT PRIMARY KEY,
                username TEXT UNIQUE NOT NULL,
                password_hash TEXT NOT NULL,
                role TEXT NOT NULL DEFAULT 'user',
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP
            );

            CREATE TABLE IF NOT EXISTS libraries (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                root_path TEXT NOT NULL,
                type TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS media (
                id TEXT PRIMARY KEY,
                library_id TEXT NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
                title TEXT NOT NULL,
                series TEXT,
                volume INTEGER,
                file_path TEXT UNIQUE NOT NULL,
                format TEXT NOT NULL,
                page_count INTEGER,
                cover_cache_path TEXT,
                added_at DATETIME DEFAULT CURRENT_TIMESTAMP
            );

            CREATE INDEX IF NOT EXISTS idx_media_library ON media(library_id);
            CREATE INDEX IF NOT EXISTS idx_media_series ON media(series);

            CREATE TABLE IF NOT EXISTS reading_progress (
                user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                media_id TEXT NOT NULL REFERENCES media(id) ON DELETE CASCADE,
                current_page INTEGER NOT NULL DEFAULT 0,
                is_completed INTEGER NOT NULL DEFAULT 0,
                last_read_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (user_id, media_id)
            );
            """);
    }
}
