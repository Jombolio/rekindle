using System.Net.Http.Json;
using System.Text.Json.Serialization;

namespace Rekindle.Core.Update;

/// One downloadable file attached to a release.
public sealed record ReleaseAsset(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("browser_download_url")] string DownloadUrl,
    [property: JsonPropertyName("size")] long Size);

/// A release as Gitea's API returns it (the same field names as GitHub's).
public sealed record Release(
    [property: JsonPropertyName("tag_name")] string TagName,
    [property: JsonPropertyName("name")] string? Name,
    [property: JsonPropertyName("prerelease")] bool IsPreRelease,
    [property: JsonPropertyName("draft")] bool IsDraft,
    [property: JsonPropertyName("html_url")] string? HtmlUrl,
    [property: JsonPropertyName("assets")] IReadOnlyList<ReleaseAsset>? Assets)
{
    /// The version from the tag, falling back to the release name.
    [JsonIgnore]
    public SemVersion? Version => SemVersion.TryParse(TagName) ?? SemVersion.TryParse(Name);

    public ReleaseAsset? FindAsset(string name) =>
        Assets?.FirstOrDefault(a => string.Equals(a.Name, name, StringComparison.OrdinalIgnoreCase));
}

/// <summary>
/// Reads releases from a Gitea repository, e.g. https://git.example.com/owner/repo.
/// </summary>
public sealed class ReleaseFeed(HttpClient http, Uri repositoryUrl)
{
    /// Enough to always include the newest stable release and pre-release.
    private const int PageSize = 50;

    public Uri RepositoryUrl { get; } = repositoryUrl;

    public async Task<IReadOnlyList<Release>> GetReleasesAsync(CancellationToken ct = default)
    {
        return await http.GetFromJsonAsync<List<Release>>(ReleasesApiUrl(RepositoryUrl), ct) ?? [];
    }

    /// https://host[/prefix]/owner/repo → https://host[/prefix]/api/v1/repos/owner/repo/releases,
    /// keeping any sub-path Gitea is served under.
    public static Uri ReleasesApiUrl(Uri repositoryUrl)
    {
        var segments = repositoryUrl.AbsolutePath.Trim('/').Split('/');
        if (segments.Length < 2 || segments.Any(string.IsNullOrEmpty))
            throw new InvalidOperationException(
                $"Update source '{repositoryUrl}' must be a repository URL like https://host/owner/repo.");

        var prefix = string.Join('/', segments[..^2]);
        var owner = segments[^2];
        var repo = segments[^1];
        var path = (prefix.Length > 0 ? $"/{prefix}" : "") + $"/api/v1/repos/{owner}/{repo}/releases";
        return new UriBuilder(repositoryUrl) { Path = path, Query = $"limit={PageSize}" }.Uri;
    }

    /// <summary>
    /// The highest-versioned published release, or null if there is none.
    /// Picks by version rather than date, so a late patch to an old line can't
    /// hide a newer release. Drafts and unversioned tags are always skipped.
    /// </summary>
    public static Release? SelectNewest(IEnumerable<Release> releases, bool includePreReleases) =>
        releases
            .Where(r => !r.IsDraft && r.Version is not null)
            .Where(r => includePreReleases || (!r.IsPreRelease && !r.Version!.IsPreRelease))
            .MaxBy(r => r.Version);
}
