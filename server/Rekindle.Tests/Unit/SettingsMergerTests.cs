using System.Text.Json.Nodes;
using FluentAssertions;
using Rekindle.Core.Update;
using Xunit;

namespace Rekindle.Tests.Unit;

public class SettingsMergerTests
{
    // An install from before the landing page, with the administrator's own values.
    private const string OldSettings = """
        {
          "Rekindle": {
            "DataPath": "/srv/rekindle/data",
            "CachePath": "/srv/rekindle/cache",
            "CacheMaxSizeBytes": 26843545600,
            "UpdateSource": "https://git.jombo.uk/Jombo/rekindle"
          },
          "Jwt": {
            "Secret": "my-secret",
            "ExpiryDays": 7
          },
          "Urls": "http://0.0.0.0:9000"
        }
        """;

    private static string Shipped() =>
        File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "appsettings.json"));

    [Fact]
    public void KeepsEveryValue_AndAddsTheNewSettings()
    {
        var result = SettingsMerger.AddMissing(OldSettings, Shipped());

        result.Should().NotBeNull();
        var merged = JsonNode.Parse(result!.Json)!;

        merged["Rekindle"]!["DataPath"]!.GetValue<string>().Should().Be("/srv/rekindle/data");
        merged["Rekindle"]!["CachePath"]!.GetValue<string>().Should().Be("/srv/rekindle/cache");
        merged["Rekindle"]!["CacheMaxSizeBytes"]!.GetValue<long>().Should().Be(26843545600);
        merged["Jwt"]!["Secret"]!.GetValue<string>().Should().Be("my-secret");
        merged["Jwt"]!["ExpiryDays"]!.GetValue<int>().Should().Be(7);
        merged["Urls"]!.GetValue<string>().Should().Be("http://0.0.0.0:9000");

        merged["Rekindle"]!["Contacts"]!.AsArray().Should().BeEmpty();
        merged["Rekindle"]!["LandingTheme"]!.GetValue<string>().Should().Be("System");
        merged["Rekindle"]!["UpdateFallbackSource"]!.GetValue<string>().Should().Be("https://github.com/Jombolio/rekindle");
        merged["Jwt"]!["Issuer"]!.GetValue<string>().Should().Be("Rekindle");

        result.Added.Should().Contain(["Rekindle:Contacts", "Rekindle:LandingTheme", "Jwt:Issuer", "Logging", "AllowedHosts"]);
        result.Added.Should().NotContain(k => k.StartsWith("Rekindle:DataPath") || k == "Urls" || k == "Jwt:Secret");
    }

    [Fact]
    public void KeepsTheOrderOfExistingSettings()
    {
        var json = SettingsMerger.AddMissing(OldSettings, Shipped())!.Json;
        json.IndexOf("\"DataPath\"").Should().BeLessThan(json.IndexOf("\"CachePath\""));
        json.IndexOf("\"Rekindle\"").Should().BeLessThan(json.IndexOf("\"Jwt\""));
    }

    [Fact]
    public void NothingToAdd_IsNull()
    {
        SettingsMerger.AddMissing(Shipped(), Shipped()).Should().BeNull();
    }

    [Fact]
    public void KeysMatchWithoutCase()
    {
        var result = SettingsMerger.AddMissing("""{"rekindle": {"landingtheme": "Dark"}}""",
            """{"Rekindle": {"LandingTheme": "System", "Contacts": []}}""");

        result!.Added.Should().Equal("rekindle:Contacts");
        var merged = JsonNode.Parse(result.Json)!;
        merged["rekindle"]!["landingtheme"]!.GetValue<string>().Should().Be("Dark");
        merged.AsObject().Count.Should().Be(1);
    }

    [Fact]
    public void ArraysAndOtherKindsOfValue_AreTheUsers()
    {
        var result = SettingsMerger.AddMissing(
            """{"Rekindle": {"Contacts": [{"Name": "Discord", "Url": "https://discord.gg/x"}], "Odd": "text"}}""",
            """{"Rekindle": {"Contacts": [], "Odd": {"Nested": 1}, "New": 1}}""");

        result!.Added.Should().Equal("Rekindle:New");
        var merged = JsonNode.Parse(result.Json)!;
        merged["Rekindle"]!["Contacts"]!.AsArray().Should().HaveCount(1);
        merged["Rekindle"]!["Odd"]!.GetValue<string>().Should().Be("text");
    }

    [Theory]
    [InlineData("{\"Urls\": \"http://0.0.0.0:9000\" // my port\n}")]
    [InlineData("""{"Urls": "http://0.0.0.0:9000" /* my port */}""")]
    [InlineData("""{"Urls": "x",}""")]
    [InlineData("""not json""")]
    [InlineData("""[1, 2]""")]
    [InlineData("""{"Urls": "a", "Urls": "b"}""")]
    public void FilesItCantRewriteSafely_AreLeftAlone(string existing)
    {
        SettingsMerger.AddMissing(existing, Shipped()).Should().BeNull();
    }

    [Fact]
    public void KeepsLineEndingsAndIndent()
    {
        var existing = "{\r\n    \"Urls\": \"http://0.0.0.0:9000\"\r\n}\r\n";

        var json = SettingsMerger.AddMissing(existing, """{"AllowedHosts": "*"}""")!.Json;

        json.Should().Be("{\r\n    \"Urls\": \"http://0.0.0.0:9000\",\r\n    \"AllowedHosts\": \"*\"\r\n}\r\n");
    }

    [Fact]
    public void DoesNotEscapeUrls()
    {
        var json = SettingsMerger.AddMissing("""{"A": "https://x.example/?a=1&b=2"}""", """{"B": 1}""")!.Json;
        json.Should().Contain("https://x.example/?a=1&b=2");
    }
}
