using Microsoft.Data.Sqlite;

namespace Rekindle.Core.Database;

public class DbConnectionFactory(string connectionString)
{
    public SqliteConnection Create()
    {
        var connection = new SqliteConnection(connectionString);
        connection.Open();
        using var cmd = connection.CreateCommand();
        // foreign_keys is a PER-CONNECTION pragma that defaults OFF, so it must be
        // set on every connection — not just the init one — or the schema's
        // ON DELETE CASCADE constraints silently no-op and deletes leave orphans.
        cmd.CommandText = "PRAGMA busy_timeout=5000; PRAGMA foreign_keys=ON;";
        cmd.ExecuteNonQuery();
        return connection;
    }
}
