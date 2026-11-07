using System.Text.Json.Nodes;
using FluentAssertions;
using Microsoft.AspNetCore.Hosting;
using Rekindle.Tests.Helpers;
using Rekindle.Tests.Unit;
using Xunit;

namespace Rekindle.Tests.Integration;

public class SettingsUpgradeOnStartTests : IClassFixture<TestWebApplicationFactory>, IDisposable
{
    private readonly TestWebApplicationFactory factory;
    private readonly string _dir = Path.Combine(Path.GetTempPath(), $"rekindle-start-{Guid.NewGuid():N}");

    public SettingsUpgradeOnStartTests(TestWebApplicationFactory factory)
    {
        this.factory = factory;
        Directory.CreateDirectory(_dir);
    }

    public void Dispose() => TempCleanup.DeleteDirectory(_dir);

    [Fact]
    public async Task StartingTheServer_AddsTheNewSettingsToAnOlderFile()
    {
        var path = Path.Combine(_dir, "appsettings.json");
        File.WriteAllText(path, SettingsUpgradeTests.AdminFileFrom161);

        using var server = factory.WithWebHostBuilder(builder => builder.UseContentRoot(_dir));
        var html = await server.CreateClient().GetStringAsync("/");
        html.Should().Contain("<title>Rekindle</title>");

        var json = JsonNode.Parse(File.ReadAllText(path))!;
        json["Rekindle"]!["LandingTheme"]!.GetValue<string>().Should().Be("System");
        json["Rekindle"]!["Contacts"]!.AsArray().Should().BeEmpty();
        json["Urls"]!.GetValue<string>().Should().Be("http://0.0.0.0:27055");
        json["Rekindle"]!["CacheMaxSizeBytes"]!.GetValue<long>().Should().Be(32212254720);
    }

    [Fact]
    public void TheBuiltInDefaults_MatchTheShippedFile()
    {
        using var stream = typeof(Program).Assembly
            .GetManifestResourceStream("Rekindle.Server.appsettings.default.json");
        stream.Should().NotBeNull();
        using var reader = new StreamReader(stream!);

        JsonNode.DeepEquals(
                JsonNode.Parse(reader.ReadToEnd()),
                JsonNode.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "appsettings.json"))))
            .Should().BeTrue();
    }
}
