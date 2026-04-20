using Microsoft.Data.Sqlite;

namespace Rekindle.Core.Database;

public class DbConnectionFactory(string connectionString)
{
    public SqliteConnection Create()
    {
        var connection = new SqliteConnection(connectionString);
        connection.Open();
        return connection;
    }
}
