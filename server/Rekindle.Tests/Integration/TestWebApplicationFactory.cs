using System.Net.Http.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Rekindle.Core.Services;
using Xunit;

namespace Rekindle.Tests.Integration;

public class TestWebApplicationFactory : WebApplicationFactory<Program>, IAsyncLifetime
{
    private readonly string _tempDir = Path.Combine(Path.GetTempPath(), $"rekindle-int-{Guid.NewGuid()}");

    public const string AdminUsername = "testadmin";
    public const string AdminPassword = "TestAdmin1!";
    public string AdminToken { get; private set; } = string.Empty;

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");

        builder.ConfigureAppConfiguration((_, config) =>
        {
            config.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Rekindle:DataPath"] = Path.Combine(_tempDir, "config"),
                ["Rekindle:CachePath"] = Path.Combine(_tempDir, "cache"),
                ["Jwt:Secret"] = "integration-test-secret-key-min-32-chars!!",
                ["Jwt:Issuer"] = "Rekindle",
                ["Jwt:Audience"] = "Rekindle",
                ["Jwt:ExpiryDays"] = "30"
            });
        });
    }

    public async ValueTask InitializeAsync()
    {
        Directory.CreateDirectory(Path.Combine(_tempDir, "config"));
        Directory.CreateDirectory(Path.Combine(_tempDir, "cache"));

        // Retrieve the one-time setup token from the DI-registered service.
        var setupTokenSvc = Services.GetRequiredService<SetupTokenService>();
        var setupToken = setupTokenSvc.Generate();

        var client = CreateClient();
        var setupResp = await client.PostAsJsonAsync("/api/auth/setup",
            new { username = AdminUsername, password = AdminPassword, setupToken });

        var body = await setupResp.Content.ReadFromJsonAsync<TokenBody>();
        AdminToken = body?.Token ?? string.Empty;
    }

    public new async ValueTask DisposeAsync()
    {
        await base.DisposeAsync();
        if (Directory.Exists(_tempDir))
            Directory.Delete(_tempDir, recursive: true);
    }

    private record TokenBody(string Token);
}
