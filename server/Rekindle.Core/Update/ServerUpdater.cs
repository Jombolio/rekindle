using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text.RegularExpressions;

namespace Rekindle.Core.Update;

/// <param name="Source">The repository that answered.</param>
/// <param name="SkippedSources">Earlier sources that couldn't be reached, with why.</param>
public sealed record UpdateCheck(
    SemVersion Current,
    Release? Latest,
    Uri Source,
    IReadOnlyList<(Uri Source, string Reason)> SkippedSources)
{
    public bool IsNewer => Latest?.Version is { } v && v > Current;
    public bool UsedFallback => SkippedSources.Count > 0;
}

/// <summary>
/// Finds, downloads, verifies and installs server releases. Sources are tried
/// in order (Gitea first, GitHub as a fallback): the next one is used only when
/// a source can't be reached or answers with something unreadable, not when it
/// simply has nothing newer. Each server zip must have a "&lt;zip&gt;.sha256"
/// asset next to it; a release without one is refused rather than installed
/// unverified.
/// </summary>
public sealed partial class ServerUpdater(
    HttpClient http, IReadOnlyList<Uri> sources, SemVersion current, string assetName)
{
    public string AssetName => assetName;
    public IReadOnlyList<Uri> Sources => sources;

    public ServerUpdater(HttpClient http, Uri repositoryUrl, SemVersion current, string assetName)
        : this(http, [repositoryUrl], current, assetName) { }

    /// The release zip for this OS and CPU, or null if none is published for it.
    public static string? PlatformAssetName()
    {
        if (RuntimeInformation.OSArchitecture != Architecture.X64) return null;
        if (OperatingSystem.IsWindows()) return "RekindleServer-windows-x64.zip";
        if (OperatingSystem.IsLinux()) return "RekindleServer-linux-x64.zip";
        return null;
    }

    public async Task<UpdateCheck> CheckAsync(bool includePreReleases, CancellationToken ct = default)
    {
        if (sources.Count == 0) throw new InvalidOperationException("No update source is configured.");

        var skipped = new List<(Uri, string)>();
        foreach (var source in sources)
        {
            try
            {
                var releases = await new ReleaseFeed(http, source).GetReleasesAsync(ct);
                return new UpdateCheck(current, ReleaseFeed.SelectNewest(releases, includePreReleases), source, skipped);
            }
            catch (Exception e) when (IsUnreachable(e, ct))
            {
                skipped.Add((source, e.Message));
            }
        }

        throw new HttpRequestException(
            "No update source could be reached: " +
            string.Join("; ", skipped.Select(s => $"{s.Item1.Host}: {s.Item2}")));
    }

    /// Failures that mean "try the next source". A cancellation the caller
    /// asked for is not one of them.
    private static bool IsUnreachable(Exception e, CancellationToken ct) => e switch
    {
        HttpRequestException => true,
        System.Text.Json.JsonException => true,
        TaskCanceledException when !ct.IsCancellationRequested => true, // timeout
        _ => false,
    };

    public async Task<InstallResult> InstallAsync(
        Release release,
        string installDir,
        IEnumerable<string> protectedDirs,
        IProgress<(long Received, long? Total)>? progress = null,
        CancellationToken ct = default)
    {
        var asset = release.FindAsset(assetName)
            ?? throw new InvalidOperationException($"Release {release.TagName} has no '{assetName}'.");
        var sumsAsset = release.FindAsset(assetName + ".sha256")
            ?? throw new InvalidOperationException(
                $"Release {release.TagName} has no '{assetName}.sha256', so the download can't be verified; not installing it.");

        var expected = ParseChecksum(await http.GetStringAsync(sumsAsset.DownloadUrl, ct))
            ?? throw new InvalidDataException($"'{sumsAsset.Name}' doesn't contain a SHA-256 checksum.");

        var tempDir = Directory.CreateTempSubdirectory("rekindle-update-");
        try
        {
            var zipPath = Path.Combine(tempDir.FullName, asset.Name);
            var actual = await DownloadAsync(asset.DownloadUrl, zipPath, progress, ct);
            if (!string.Equals(actual, expected, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException(
                    $"Checksum mismatch for {asset.Name}: expected {expected}, got {actual}. Not installing it.");

            return UpdateInstaller.Install(zipPath, installDir, protectedDirs);
        }
        finally
        {
            try { tempDir.Delete(recursive: true); } catch (IOException) { }
        }
    }

    [GeneratedRegex(@"\b([0-9a-fA-F]{64})\b")]
    private static partial Regex Sha256Pattern();

    /// Accepts a bare hash or `sha256sum` output ("hash  filename").
    public static string? ParseChecksum(string text) =>
        Sha256Pattern().Match(text) is { Success: true } m ? m.Groups[1].Value.ToLowerInvariant() : null;

    /// Streams the download to disk, hashing as it goes. Returns the SHA-256.
    private async Task<string> DownloadAsync(
        string url, string path, IProgress<(long, long?)>? progress, CancellationToken ct)
    {
        using var response = await http.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, ct);
        response.EnsureSuccessStatusCode();
        var total = response.Content.Headers.ContentLength;

        await using var source = await response.Content.ReadAsStreamAsync(ct);
        await using var file = File.Create(path);
        using var sha = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);

        var buffer = new byte[81920];
        long received = 0;
        int read;
        while ((read = await source.ReadAsync(buffer, ct)) > 0)
        {
            await file.WriteAsync(buffer.AsMemory(0, read), ct);
            sha.AppendData(buffer, 0, read);
            received += read;
            progress?.Report((received, total));
        }

        return Convert.ToHexStringLower(sha.GetHashAndReset());
    }
}
