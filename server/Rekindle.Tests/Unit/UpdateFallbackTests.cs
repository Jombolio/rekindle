using System.Net;
using System.Text;
using FluentAssertions;
using Rekindle.Core.Update;
using Xunit;

namespace Rekindle.Tests.Unit;

/// Gitea first, GitHub only when Gitea can't be reached.
public class UpdateFallbackTests : IDisposable
{
    private static readonly Uri Gitea = new("https://git.example.com/Jombo/rekindle");
    private static readonly Uri GitHub = new("https://github.com/Jombolio/rekindle");
    private readonly TimeSpan _savedTimeout = ReleaseFeed.ListTimeout;

    // Short, so the "Gitea hangs" case falls back quickly.
    public UpdateFallbackTests() => ReleaseFeed.ListTimeout = TimeSpan.FromMilliseconds(300);
    public void Dispose() => ReleaseFeed.ListTimeout = _savedTimeout;

    public enum Mode { Ok, Empty, Http503, Refused, Junk, Hang }

    private const string GitHubReleases =
        """[{"tag_name":"v1.5.0","name":"Rekindle v1.5.0","prerelease":false,"draft":false,"assets":[]}]""";
    private const string GiteaReleases =
        """[{"tag_name":"v1.5.0-beta.2","name":"b2","prerelease":true,"draft":false,"assets":[]}]""";

    /// Gitea behaves as told; GitHub always answers with one stable release.
    private sealed class Sources(Mode gitea) : HttpMessageHandler
    {
        public List<string> Hosts { get; } = [];

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            var host = request.RequestUri!.Host;
            Hosts.Add(host);
            if (host == "api.github.com") return Json(GitHubReleases);

            switch (gitea)
            {
                case Mode.Ok: return Json(GiteaReleases);
                case Mode.Empty: return Json("[]");
                case Mode.Http503: return new HttpResponseMessage(HttpStatusCode.ServiceUnavailable);
                case Mode.Refused: throw new HttpRequestException("Connection refused");
                case Mode.Junk: return Json("<html>maintenance</html>");
                default:
                    await Task.Delay(Timeout.Infinite, ct);
                    throw new InvalidOperationException("unreachable");
            }
        }

        private static HttpResponseMessage Json(string body) =>
            new(HttpStatusCode.OK) { Content = new StringContent(body, Encoding.UTF8, "application/json") };
    }

    private static ServerUpdater Updater(Sources handler, params Uri[] sources) =>
        new(new HttpClient(handler), sources, SemVersion.TryParse("1.5.0-beta.1")!, "RekindleServer-linux-x64.zip");

    [Fact]
    public async Task GiteaAnswers_GitHubIsNeverAsked()
    {
        var handler = new Sources(Mode.Ok);

        var check = await Updater(handler, Gitea, GitHub).CheckAsync(includePreReleases: true);

        check.Source.Should().Be(Gitea);
        check.UsedFallback.Should().BeFalse();
        check.Latest!.TagName.Should().Be("v1.5.0-beta.2");
        handler.Hosts.Should().NotContain("api.github.com");
    }

    [Fact]
    public async Task GiteaWithNothingNewer_IsAnAnswer_NotAFailure()
    {
        var handler = new Sources(Mode.Empty);

        var check = await Updater(handler, Gitea, GitHub).CheckAsync(includePreReleases: false);

        check.Source.Should().Be(Gitea);
        check.Latest.Should().BeNull();
        handler.Hosts.Should().NotContain("api.github.com");
    }

    [Theory]
    [InlineData(Mode.Http503)]
    [InlineData(Mode.Refused)]
    [InlineData(Mode.Junk)]
    [InlineData(Mode.Hang)]
    public async Task UnreachableGitea_FallsBackToGitHub(Mode gitea)
    {
        var handler = new Sources(gitea);

        var check = await Updater(handler, Gitea, GitHub).CheckAsync(includePreReleases: false);

        check.Source.Should().Be(GitHub);
        check.UsedFallback.Should().BeTrue();
        check.SkippedSources.Single().Source.Should().Be(Gitea);
        check.Latest!.TagName.Should().Be("v1.5.0");
        check.IsNewer.Should().BeTrue();
        handler.Hosts.Should().Contain("api.github.com");
    }

    [Fact]
    public async Task BothUnreachable_NamesEverySource()
    {
        var act = () => Updater(new Sources(Mode.Refused), Gitea).CheckAsync(includePreReleases: false);

        (await act.Should().ThrowAsync<HttpRequestException>())
            .WithMessage("*git.example.com*Connection refused*");
    }

    [Fact]
    public async Task CallerCancellation_IsNotTreatedAsUnreachable()
    {
        using var cts = new CancellationTokenSource();
        await cts.CancelAsync();
        var handler = new Sources(Mode.Hang);

        var act = () => Updater(handler, Gitea, GitHub).CheckAsync(includePreReleases: false, cts.Token);

        await act.Should().ThrowAsync<OperationCanceledException>();
        handler.Hosts.Should().NotContain("api.github.com");
    }
}
