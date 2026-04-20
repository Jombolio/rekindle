using Microsoft.Extensions.Logging.Abstractions;
using Rekindle.Core.Database;

namespace Rekindle.Tests.Helpers;

public sealed class TestDatabase : IDisposable
{
    private readonly string _path = Path.Combine(Path.GetTempPath(), $"rekindle-test-{Guid.NewGuid()}.db");

    public DbConnectionFactory Factory { get; }

    public TestDatabase()
    {
        Factory = new DbConnectionFactory($"Data Source={_path};");
        var initializer = new DbInitializer(Factory, NullLogger<DbInitializer>.Instance);
        initializer.InitializeAsync().GetAwaiter().GetResult();
    }

    public void Dispose()
    {
        if (File.Exists(_path))
            File.Delete(_path);
    }
}
