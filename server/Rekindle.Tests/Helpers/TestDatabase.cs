using Microsoft.Extensions.Logging.Abstractions;
using Rekindle.Core.Database;

namespace Rekindle.Tests.Helpers;

public sealed class TestDatabase : IDisposable
{
    private readonly string _path = Path.Combine(Path.GetTempPath(), $"rekindle-test-{Guid.NewGuid()}.db");

    public DbConnectionFactory Factory { get; }

    public TestDatabase()
    {
        // No pooling: a pooled connection keeps the file open after the test
        // disposes it, and Windows can't delete an open file (Linux can,
        // which is why this only fails on Windows).
        Factory = new DbConnectionFactory($"Data Source={_path};Pooling=False;");
        var initializer = new DbInitializer(Factory, NullLogger<DbInitializer>.Instance);
        initializer.InitializeAsync().GetAwaiter().GetResult();
    }

    public void Dispose()
    {
        TempCleanup.DeleteFile(_path);
    }
}
