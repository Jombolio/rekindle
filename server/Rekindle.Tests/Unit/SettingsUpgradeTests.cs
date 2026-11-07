using System.Text.Json.Nodes;
using FluentAssertions;
using Rekindle.Core.Update;
using Rekindle.Tests.Helpers;
using Xunit;

namespace Rekindle.Tests.Unit;

public class SettingsUpgradeTests : IDisposable
{
    // An administrator's file from before 1.6.2, as it was left by a 1.6.1
    // --update: their own port and cache size, none of the newer settings.
    public const string AdminFileFrom161 = """
        {
          "Rekindle": {
            "DataPath": "data",
            "CachePath": "data/cache",
            "CacheMaxSizeBytes": 32212254720
          },
          "Jwt": {
            "Secret": "",
            "Issuer": "Rekindle",
            "Audience": "Rekindle",
            "ExpiryDays": 30
          },
          "Logging": {
            "LogLevel": {
              "Default": "Information",
              "Microsoft.AspNetCore": "Warning"
            }
          },
          "AllowedHosts": "*",
          "Urls": "http://0.0.0.0:27055"
        }
        """;

    private readonly string _dir = Path.Combine(Path.GetTempPath(), $"rekindle-settings-{Guid.NewGuid():N}");
    private string SettingsPath => Path.Combine(_dir, "appsettings.json");

    public SettingsUpgradeTests() => Directory.CreateDirectory(_dir);
    public void Dispose() => TempCleanup.DeleteDirectory(_dir);

    private static string Shipped() =>
        File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "appsettings.json"));

    [Fact]
    public void AnOlderFile_GainsTheNewSettings_AndKeepsItsOwn()
    {
        File.WriteAllText(SettingsPath, AdminFileFrom161);

        var result = SettingsMerger.UpgradeFile(SettingsPath, Shipped());

        result!.Added.Should().Contain(["Rekindle:UpdateSource", "Rekindle:UpdateFallbackSource",
            "Rekindle:Contacts", "Rekindle:LandingTheme"]);
        var json = JsonNode.Parse(File.ReadAllText(SettingsPath))!;
        json["Urls"]!.GetValue<string>().Should().Be("http://0.0.0.0:27055");
        json["Rekindle"]!["CacheMaxSizeBytes"]!.GetValue<long>().Should().Be(32212254720);
        json["Rekindle"]!["LandingTheme"]!.GetValue<string>().Should().Be("System");
        json["Rekindle"]!["Contacts"]!.AsArray().Should().BeEmpty();
        Directory.GetFiles(_dir).Should().ContainSingle("no temporary file is left behind");
    }

    [Fact]
    public void AnUpToDateFile_IsNotRewritten()
    {
        File.WriteAllText(SettingsPath, Shipped());
        var written = File.GetLastWriteTimeUtc(SettingsPath).AddMinutes(-5);
        File.SetLastWriteTimeUtc(SettingsPath, written);

        SettingsMerger.UpgradeFile(SettingsPath, Shipped()).Should().BeNull();

        File.GetLastWriteTimeUtc(SettingsPath).Should().Be(written);
    }

    [Fact]
    public void NoFile_IsNotCreated()
    {
        SettingsMerger.UpgradeFile(SettingsPath, Shipped()).Should().BeNull();
        File.Exists(SettingsPath).Should().BeFalse();
    }

    [Fact]
    public void AFileWithComments_IsLeftAlone()
    {
        const string commented = "{\n  // my port\n  \"Urls\": \"http://0.0.0.0:27055\"\n}\n";
        File.WriteAllText(SettingsPath, commented);

        SettingsMerger.UpgradeFile(SettingsPath, Shipped()).Should().BeNull();

        File.ReadAllText(SettingsPath).Should().Be(commented);
    }

    [Fact]
    public void KeepsTheFilesPermissions()
    {
        if (OperatingSystem.IsWindows()) return;
        File.WriteAllText(SettingsPath, AdminFileFrom161);
        const UnixFileMode ownerOnly = UnixFileMode.UserRead | UnixFileMode.UserWrite;
        File.SetUnixFileMode(SettingsPath, ownerOnly);

        SettingsMerger.UpgradeFile(SettingsPath, Shipped());

        File.GetUnixFileMode(SettingsPath).Should().Be(ownerOnly);
    }
}
