using Microsoft.Data.Sqlite;

namespace Rekindle.Core.Database;

public class DbConnectionFactory(string connectionString)
{
    public SqliteConnection Create()
    {
        var connection = new SqliteConnection(connectionString);
        connection.Open();
        using var cmd = connection.CreateCommand();
        cmd.CommandText = "PRAGMA busy_timeout=5000;";
        cmd.ExecuteNonQuery();
        return connection;
    }
}
