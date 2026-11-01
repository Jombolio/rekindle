using System.IO.Compression;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using FluentAssertions;
using Rekindle.Core.Update;
using Rekindle.Tests.Helpers;
using Xunit;

namespace Rekindle.Tests.Unit;

public class SemVersionTests
{
    [Theory]
    [InlineData("1.5.0", 1, 5, 0, null)]
    [InlineData("v1.5.0", 1, 5, 0, null)]
    [InlineData("1.5.0-beta.1", 1, 5, 0, "beta.1")]
    [InlineData("v2.0.0-rc.1+abc123", 2, 0, 0, "rc.1")]
    [InlineData("1.4.1+0123456789abcdef", 1, 4, 1, null)]
    public void Parses(string text, int major, int minor, int patch, string? pre)
    {
        SemVersion.TryParse(text).Should().Be(new SemVersion(major, minor, patch, pre));
    }

    [Theory]
    [InlineData("")]
    [InlineData("Release")]
    [InlineData("Pre-release")]
    [InlineData("1.5")]
    [InlineData("1.5.0-")]
    [InlineData("1.5.0-beta..1")]
    public void RejectsNonVersions(string text)
    {
        SemVersion.TryParse(text).Should().BeNull();
    }

    [Fact]
    public void OrdersPerSemver()
    {
        // Ascending, straight from semver.org §11 plus a few of our own tags.
        string[] ordered =
        [
            "1.4.1",
            "1.5.0-alpha", "1.5.0-alpha.1", "1.5.0-alpha.beta", "1.5.0-beta",
            "1.5.0-beta.2", "1.5.0-beta.11", "1.5.0-rc.1", "1.5.0",
            "1.5.1", "1.10.0", "2.0.0",
        ];
        var parsed = ordered.Select(v => SemVersion.TryParse(v)!).ToList();

        parsed.Should().BeInAscendingOrder();
        for (var i = 1; i < parsed.Count; i++)
            (parsed[i - 1] < parsed[i]).Should().BeTrue($"{ordered[i - 1]} < {ordered[i]}");
    }

    [Fact]
    public void BuildMetadataIsIgnored()
    {
        SemVersion.TryParse("1.5.0+aaa")!.CompareTo(SemVersion.TryParse("1.5.0+bbb")).Should().Be(0);
    }
}

public class ReleaseFeedTests
{
    private static Release R(string tag, bool pre = false, bool draft = false) =>
        new(tag, $"Rekindle {tag}", pre, draft, null, []);

    [Fact]
    public void Stable_PicksHighestNonPreRelease()
    {
        var releases = new[] { R("v1.4.0"), R("v1.4.1"), R("v1.5.0-beta.1", pre: true), R("v1.3.0") };

        ReleaseFeed.SelectNewest(releases, includePreReleases: false)!.TagName.Should().Be("v1.4.1");
    }

    [Fact]
    public void Dev_IncludesPreReleases()
    {
        var releases = new[] { R("v1.4.1"), R("v1.5.0-beta.1", pre: true) };

        ReleaseFeed.SelectNewest(releases, includePreReleases: true)!.TagName.Should().Be("v1.5.0-beta.1");
    }

    [Fact]
    public void Dev_PrefersTheReleaseOverItsOwnPreReleases()
    {
        var releases = new[] { R("v1.5.0-rc.1", pre: true), R("v1.5.0") };

        ReleaseFeed.SelectNewest(releases, includePreReleases: true)!.TagName.Should().Be("v1.5.0");
    }

    [Fact]
    public void SkipsDraftsAndUnversionedTags()
    {
        // "Release" and "Pre-release" are real old tags in this repo.
        var releases = new[] { R("v9.9.9", draft: true), new Release("Release", "Release", false, false, null, []), R("v1.4.1") };

        ReleaseFeed.SelectNewest(releases, includePreReleases: true)!.TagName.Should().Be("v1.4.1");
    }

    [Fact]
    public void Stable_IgnoresAPreReleaseTagNotFlaggedAsOne()
    {
        // Someone forgot to tick "pre-release" on a beta tag.
        var releases = new[] { R("v1.4.1"), R("v1.5.0-beta.1") };

        ReleaseFeed.SelectNewest(releases, includePreReleases: false)!.TagName.Should().Be("v1.4.1");
    }

    [Fact]
    public void NoReleases_IsNull()
    {
        ReleaseFeed.SelectNewest([], includePreReleases: true).Should().BeNull();
    }

    [Theory]
    [InlineData("https://git.jombo.uk/Jombo/rekindle", "https://git.jombo.uk/api/v1/repos/Jombo/rekindle/releases?limit=50")]
    [InlineData("https://git.jombo.uk/Jombo/rekindle/", "https://git.jombo.uk/api/v1/repos/Jombo/rekindle/releases?limit=50")]
    [InlineData("https://example.com/gitea/Jombo/rekindle", "https://example.com/gitea/api/v1/repos/Jombo/rekindle/releases?limit=50")]
    [InlineData("https://github.com/Jombolio/rekindle", "https://api.github.com/repos/Jombolio/rekindle/releases?per_page=50")]
    public void ReleasesApiUrl_KeepsAnySubPath(string repo, string expected)
    {
        ReleaseFeed.ReleasesApiUrl(new Uri(repo)).ToString().Should().Be(expected);
    }

    [Fact]
    public void ReleasesApiUrl_RejectsNonRepositoryUrls()
    {
        var act = () => ReleaseFeed.ReleasesApiUrl(new Uri("https://git.jombo.uk/"));

        act.Should().Throw<InvalidOperationException>();
    }
}

public class UpdateInstallerTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), $"rekindle-install-{Guid.NewGuid():N}");
    private string Install => Path.Combine(_root, "install");
    private string Data => Path.Combine(Install, "data");

    public UpdateInstallerTests()
    {
        // An existing installation: binaries, a customised config, a data
        // folder with a database, and a file of the user's own.
        Directory.CreateDirectory(Path.Combine(Data, "cache"));
        File.WriteAllText(Path.Combine(Install, "Rekindle.Server"), "old binary");
        File.WriteAllText(Path.Combine(Install, "libvips.so.42"), "old lib");
        File.WriteAllText(Path.Combine(Install, "appsettings.json"), """{"custom": true}""");
        File.WriteAllText(Path.Combine(Install, "appsettings.Production.json"), """{"prod": true}""");
        File.WriteAllText(Path.Combine(Data, "rekindle.db"), "database");
        File.WriteAllText(Path.Combine(Install, "notes.txt"), "mine");
        if (!OperatingSystem.IsWindows())
            File.SetUnixFileMode(Path.Combine(Install, "Rekindle.Server"), (UnixFileMode)0b111_101_101);
    }

    public void Dispose() => TempCleanup.DeleteDirectory(_root);

    private string Zip(params (string Name, string Content)[] entries)
    {
        var path = Path.Combine(_root, $"release-{Guid.NewGuid():N}.zip");
        using var zip = ZipFile.Open(path, ZipArchiveMode.Create);
        foreach (var (name, content) in entries)
        {
            using var stream = zip.CreateEntry(name).Open();
            stream.Write(Encoding.UTF8.GetBytes(content));
        }
        return path;
    }

    private string Read(string relative) => File.ReadAllText(Path.Combine(Install, relative));

    private static readonly (string, string)[] Release =
    [
        ("Rekindle.Server", "new binary"),
        ("libvips.so.42", "new lib"),
        ("pdfium.so", "new pdfium"),
        ("appsettings.json", """{"shipped": true}"""),
        ("LICENSE", "license"),
    ];

    [Fact]
    public void ReplacesShippedFiles_AndKeepsConfigDataAndUserFiles()
    {
        var result = UpdateInstaller.Install(Zip(Release), Install, [Data]);

        Read("Rekindle.Server").Should().Be("new binary");
        Read("libvips.so.42").Should().Be("new lib");
        Read("pdfium.so").Should().Be("new pdfium");
        Read("appsettings.json").Should().Be("""{"custom": true}""", "existing configuration is never overwritten");
        Read("appsettings.Production.json").Should().Be("""{"prod": true}""");
        Read("notes.txt").Should().Be("mine");
        File.ReadAllText(Path.Combine(Data, "rekindle.db")).Should().Be("database");

        result.Replaced.Should().BeEquivalentTo("Rekindle.Server", "libvips.so.42");
        result.Added.Should().BeEquivalentTo("pdfium.so", "LICENSE");
        result.KeptExisting.Should().BeEquivalentTo("appsettings.json");
    }

    [Fact]
    public void LeavesNoBackupsOrStagingBehind()
    {
        UpdateInstaller.Install(Zip(Release), Install, [Data]);

        Directory.EnumerateFileSystemEntries(Install)
            .Select(Path.GetFileName)
            .Should().NotContain(n => n!.Contains(".rekindle"));
    }

    [Fact]
    public void InstallsTheShippedConfig_WhenThereIsNone()
    {
        File.Delete(Path.Combine(Install, "appsettings.json"));

        UpdateInstaller.Install(Zip(Release), Install, [Data]);

        Read("appsettings.json").Should().Be("""{"shipped": true}""");
    }

    [Fact]
    public void KeepsTheExecutableBit()
    {
        if (OperatingSystem.IsWindows()) return;

        UpdateInstaller.Install(Zip(Release), Install, [Data]);

        File.GetUnixFileMode(Path.Combine(Install, "Rekindle.Server"))
            .Should().HaveFlag(UnixFileMode.UserExecute);
    }

    [Fact]
    public void RejectsEntriesOutsideTheInstallDirectory()
    {
        var zip = Zip(("Rekindle.Server", "new"), ("../escaped.txt", "evil"));

        var act = () => UpdateInstaller.Install(zip, Install, [Data]);

        act.Should().Throw<InvalidDataException>();
        File.Exists(Path.Combine(_root, "escaped.txt")).Should().BeFalse();
        Read("Rekindle.Server").Should().Be("old binary", "nothing is installed when the archive is rejected");
    }

    [Fact]
    public void RejectsArchivesThatWriteIntoTheDataDirectory()
    {
        var zip = Zip(("Rekindle.Server", "new"), ("data/rekindle.db", "overwritten"));

        var act = () => UpdateInstaller.Install(zip, Install, [Data]);

        act.Should().Throw<InvalidDataException>();
        File.ReadAllText(Path.Combine(Data, "rekindle.db")).Should().Be("database");
        Read("Rekindle.Server").Should().Be("old binary");
    }

    [Fact]
    public void RollsBackEverything_WhenAFileCannotBePlaced()
    {
        // A directory where the release has a file makes the move fail part-way.
        Directory.CreateDirectory(Path.Combine(Install, "pdfium.so"));
        var zip = Zip(("Rekindle.Server", "new binary"), ("libvips.so.42", "new lib"), ("pdfium.so", "x"));

        var act = () => UpdateInstaller.Install(zip, Install, [Data]);

        act.Should().Throw<Exception>();
        Read("Rekindle.Server").Should().Be("old binary");
        Read("libvips.so.42").Should().Be("old lib");
        Directory.EnumerateFiles(Install).Select(Path.GetFileName)
            .Should().NotContain(n => n!.EndsWith(".rekindle-old"));
    }

    [Fact]
    public void CleanupLeftovers_DeletesListedFilesAndTheList()
    {
        var leftover = Path.Combine(Install, "Rekindle.Server.exe.rekindle-old");
        File.WriteAllText(leftover, "old");
        var list = Path.Combine(Install, ".rekindle-update-leftovers");
        File.WriteAllLines(list, [leftover]);

        UpdateInstaller.CleanupLeftovers(Install);

        File.Exists(leftover).Should().BeFalse();
        File.Exists(list).Should().BeFalse();
    }
}

public class ServerUpdaterTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), $"rekindle-updater-{Guid.NewGuid():N}");
    private const string Asset = "RekindleServer-linux-x64.zip";
    private static readonly Uri Repo = new("https://git.example.com/Jombo/rekindle");

    public ServerUpdaterTests()
    {
        Directory.CreateDirectory(Path.Combine(_root, "data"));
        File.WriteAllText(Path.Combine(_root, "Rekindle.Server"), "old");
    }

    public void Dispose() => TempCleanup.DeleteDirectory(_root);

    private static byte[] ZipBytes()
    {
        using var ms = new MemoryStream();
        using (var zip = new ZipArchive(ms, ZipArchiveMode.Create, leaveOpen: true))
        {
            using var s = zip.CreateEntry("Rekindle.Server").Open();
            s.Write("new"u8);
        }
        return ms.ToArray();
    }

    /// Serves a release list plus the zip and its checksum file.
    private sealed class FakeGitea(byte[] zip, string? sums, params Release[] releases) : HttpMessageHandler
    {
        public List<string> Requests { get; } = [];

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            var url = request.RequestUri!.ToString();
            Requests.Add(url);
            HttpResponseMessage Ok(HttpContent c) => new(HttpStatusCode.OK) { Content = c };

            if (url.Contains("/api/v1/repos/Jombo/rekindle/releases"))
                return Task.FromResult(Ok(new StringContent(JsonSerializer.Serialize(releases), Encoding.UTF8, "application/json")));
            if (url.EndsWith(".zip.sha256") && sums is not null)
                return Task.FromResult(Ok(new StringContent(sums)));
            if (url.EndsWith(".zip"))
                return Task.FromResult(Ok(new ByteArrayContent(zip)));
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.NotFound));
        }
    }

    private static Release ReleaseWith(string tag, bool pre, bool withSums) => new(
        tag, tag, pre, false, null,
        [
            new ReleaseAsset(Asset, $"https://git.example.com/dl/{tag}/{Asset}", 0),
            .. withSums ? [new ReleaseAsset(Asset + ".sha256", $"https://git.example.com/dl/{tag}/{Asset}.sha256", 0)] : Array.Empty<ReleaseAsset>(),
        ]);

    private ServerUpdater Updater(FakeGitea gitea, string current = "1.4.1") =>
        new(new HttpClient(gitea), Repo, SemVersion.TryParse(current)!, Asset);

    [Fact]
    public async Task Check_ReportsNewerStableAndPreRelease()
    {
        var gitea = new FakeGitea(ZipBytes(), null,
            ReleaseWith("v1.4.1", false, true), ReleaseWith("v1.5.0-beta.1", true, true));
        var updater = Updater(gitea);

        (await updater.CheckAsync(includePreReleases: false)).IsNewer.Should().BeFalse();
        var dev = await updater.CheckAsync(includePreReleases: true);
        dev.IsNewer.Should().BeTrue();
        dev.Latest!.TagName.Should().Be("v1.5.0-beta.1");
    }

    [Fact]
    public async Task Check_NeverOffersADowngrade()
    {
        // A beta user running the stable --update must not go back to 1.4.1.
        var gitea = new FakeGitea(ZipBytes(), null, ReleaseWith("v1.4.1", false, true));

        (await Updater(gitea, current: "1.5.0-beta.1").CheckAsync(false)).IsNewer.Should().BeFalse();
    }

    [Fact]
    public async Task Install_VerifiesTheChecksumAndInstalls()
    {
        var zip = ZipBytes();
        var hash = Convert.ToHexStringLower(SHA256.HashData(zip));
        var release = ReleaseWith("v1.5.0-beta.1", true, true);
        var gitea = new FakeGitea(zip, $"{hash}  {Asset}\n", release);

        await Updater(gitea).InstallAsync(release, _root, [Path.Combine(_root, "data")]);

        File.ReadAllText(Path.Combine(_root, "Rekindle.Server")).Should().Be("new");
    }

    [Fact]
    public async Task Install_RefusesAChecksumMismatch()
    {
        var release = ReleaseWith("v1.5.0-beta.1", true, true);
        var gitea = new FakeGitea(ZipBytes(), new string('0', 64), release);

        var act = () => Updater(gitea).InstallAsync(release, _root, [Path.Combine(_root, "data")]);

        await act.Should().ThrowAsync<InvalidDataException>().WithMessage("*mismatch*");
        File.ReadAllText(Path.Combine(_root, "Rekindle.Server")).Should().Be("old");
    }

    [Fact]
    public async Task Install_RefusesAReleaseWithoutAChecksum()
    {
        var release = ReleaseWith("v1.5.0-beta.1", true, withSums: false);
        var gitea = new FakeGitea(ZipBytes(), null, release);

        var act = () => Updater(gitea).InstallAsync(release, _root, [Path.Combine(_root, "data")]);

        await act.Should().ThrowAsync<InvalidOperationException>().WithMessage("*can't be verified*");
        gitea.Requests.Should().NotContain(u => u.EndsWith(".zip"), "nothing is downloaded without a checksum");
    }

    [Theory]
    [InlineData("ABCDEF0123456789abcdef0123456789ABCDEF0123456789abcdef0123456789  RekindleServer-linux-x64.zip")]
    [InlineData("abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789")]
    public void ParseChecksum_AcceptsSha256sumOutputOrABareHash(string text)
    {
        ServerUpdater.ParseChecksum(text).Should().Be("abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789");
    }
}
