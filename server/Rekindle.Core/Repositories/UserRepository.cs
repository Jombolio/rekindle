using Dapper;
using Rekindle.Core.Database;
using Rekindle.Core.Models;

namespace Rekindle.Core.Repositories;

public class UserRepository(DbConnectionFactory factory)
{
    private const string SelectColumns =
        "id, username, password_hash AS PasswordHash, permission_level AS PermissionLevel, created_at AS CreatedAt";

    public async Task<User?> GetByUsernameAsync(string username)
    {
        using var conn = factory.Create();
        return await conn.QuerySingleOrDefaultAsync<User>(
            $"SELECT {SelectColumns} FROM users WHERE username = @username;",
            new { username });
    }

    public async Task<User?> GetByIdAsync(string id)
    {
        using var conn = factory.Create();
        return await conn.QuerySingleOrDefaultAsync<User>(
            $"SELECT {SelectColumns} FROM users WHERE id = @id;",
            new { id });
    }

    public async Task<IEnumerable<User>> GetAllAsync()
    {
        using var conn = factory.Create();
        return await conn.QueryAsync<User>(
            $"SELECT {SelectColumns} FROM users ORDER BY created_at;");
    }

    public async Task<bool> AnyExistsAsync()
    {
        using var conn = factory.Create();
        var count = await conn.ExecuteScalarAsync<int>("SELECT COUNT(*) FROM users;");
        return count > 0;
    }

    public async Task<bool> AdminExistsAsync()
    {
        using var conn = factory.Create();
        var count = await conn.ExecuteScalarAsync<int>(
            "SELECT COUNT(*) FROM users WHERE permission_level >= 4;");
        return count > 0;
    }

    public async Task InsertAsync(User user)
    {
        using var conn = factory.Create();
        await conn.ExecuteAsync(
            """
            INSERT INTO users (id, username, password_hash, role, permission_level, created_at)
            VALUES (@Id, @Username, @PasswordHash, @Role, @PermissionLevel, @CreatedAt);
            """, user);
    }

    public async Task UpdatePermissionLevelAsync(string id, int permissionLevel)
    {
        using var conn = factory.Create();
        await conn.ExecuteAsync(
            "UPDATE users SET permission_level = @permissionLevel WHERE id = @id;",
            new { id, permissionLevel });
    }

    public async Task UpdatePasswordHashAsync(string id, string passwordHash)
    {
        using var conn = factory.Create();
        await conn.ExecuteAsync(
            "UPDATE users SET password_hash = @passwordHash WHERE id = @id;",
            new { id, passwordHash });
    }

    public async Task<int> CountAsync()
    {
        using var conn = factory.Create();
        return await conn.ExecuteScalarAsync<int>("SELECT COUNT(*) FROM users;");
    }

    public async Task DeleteAsync(string id)
    {
        using var conn = factory.Create();
        await conn.ExecuteAsync("DELETE FROM users WHERE id = @id;", new { id });
    }
}
