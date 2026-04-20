using Dapper;
using Rekindle.Core.Database;
using Rekindle.Core.Models;

namespace Rekindle.Core.Repositories;

public class LibraryRepository(DbConnectionFactory factory)
{
    public async Task<IEnumerable<Library>> GetAllAsync()
    {
        using var conn = factory.Create();
        return await conn.QueryAsync<Library>(
            "SELECT id, name, root_path AS RootPath, type FROM libraries;");
    }

    public async Task<Library?> GetByIdAsync(string id)
    {
        using var conn = factory.Create();
        return await conn.QuerySingleOrDefaultAsync<Library>(
            "SELECT id, name, root_path AS RootPath, type FROM libraries WHERE id = @id;",
            new { id });
    }

    public async Task UpdateAsync(Library library)
    {
        using var conn = factory.Create();
        await conn.ExecuteAsync(
            "UPDATE libraries SET name = @Name, root_path = @RootPath, type = @Type WHERE id = @Id;",
            library);
    }

    public async Task InsertAsync(Library library)
    {
        using var conn = factory.Create();
        await conn.ExecuteAsync(
            "INSERT INTO libraries (id, name, root_path, type) VALUES (@Id, @Name, @RootPath, @Type);",
            library);
    }

    public async Task DeleteAsync(string id)
    {
        using var conn = factory.Create();
        await conn.ExecuteAsync("DELETE FROM libraries WHERE id = @id;", new { id });
    }
}
