using System.Net;
using System.Net.Http.Json;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using Rekindle.Core.Models;
using Rekindle.Core.Repositories;
using Rekindle.Tests.Helpers;
using Xunit;

namespace Rekindle.Tests.Integration;

/// Runs the progress-summary endpoint against the real database, so the SQL,
/// the library-wide load and the timestamp round-trip through SQLite are all
/// exercised. The rules themselves are covered in Unit/ProgressSummaryTests.
public class ProgressSummaryTests : IClassFixture<TestWebApplicationFactory>
{
    private readonly HttpClient _client;
    private readonly TestWebApplicationFactory _factory;

    public ProgressSummaryTests(TestWebApplicationFactory factory)
    {
        _factory = factory;
        _client = factory.CreateClient();
        _client.SetBearerToken(factory.AdminToken);
    }

    private async Task<string> CreateLibraryAsync()
    {
        var root = Path.Combine(Path.GetTempPath(), $"rekindle-summary-{Guid.NewGuid():N}");
        Directory.CreateDirectory(root);
        var resp = await _client.PostAsJsonAsync("/api/libraries", new { name = "Summary Test", rootPath = root, type = "manga" });
        resp.EnsureSuccessStatusCode();
        var lib = await resp.Content.ReadFromJsonAsync<LibraryResponse>();
        return lib!.Id;
    }

    private async Task<Media> InsertAsync(string libraryId, string type, string? parentId, int? pages, DateTime addedAt)
    {
        var media = new Media
        {
            LibraryId = libraryId,
            Title = Guid.NewGuid().ToString("N"),
            FilePath = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N")),
            Format = type == "folder" ? "folder" : "cbz",
            MediaType = type,
            ParentId = parentId,
            PageCount = pages,
            AddedAt = addedAt,
        };
        using var scope = _factory.Services.CreateScope();
        await scope.ServiceProvider.GetRequiredService<MediaRepository>().InsertAsync(media);
        return media;
    }

    private Task<HttpResponseMessage> SummaryAsync(params string[] ids) =>
        _client.PostAsJsonAsync("/api/media/progress-summary", new { ids });

    [Fact]
    public async Task Summary_ReportsSeriesProgressAndNewChapters()
    {
        var now = DateTime.UtcNow;
        var lib = await CreateLibraryAsync();
        var series = await InsertAsync(lib, "folder", null, null, now.AddDays(-10));
        var c1 = await InsertAsync(lib, "archive", series.Id, 20, now.AddDays(-10));
        var c2 = await InsertAsync(lib, "archive", series.Id, 20, now.AddDays(-10));

        // Read a quarter of chapter 1, five days ago.
        var save = await _client.PostAsJsonAsync($"/api/media/{c1.Id}/progress",
            new { currentPage = 5, isCompleted = false, lastReadAt = now.AddDays(-5) });
        save.EnsureSuccessStatusCode();

        // A chapter added yesterday, after that read.
        var c3 = await InsertAsync(lib, "archive", series.Id, null, now.AddDays(-1));

        var resp = await SummaryAsync(series.Id, c1.Id, c2.Id, c3.Id);

        resp.StatusCode.Should().Be(HttpStatusCode.OK);
        var body = (await resp.Content.ReadFromJsonAsync<List<SummaryResponse>>())!
            .ToDictionary(s => s.MediaId);

        body[series.Id].Progress.Should().BeApproximately(0.25 / 3, 1e-9);
        body[series.Id].IsCompleted.Should().BeFalse();
        body[series.Id].NewCount.Should().Be(1);

        body[c1.Id].Progress.Should().Be(0.25);
        body[c1.Id].IsNew.Should().BeFalse();
        body[c2.Id].IsNew.Should().BeFalse("it was there before the last read");
        body[c3.Id].IsNew.Should().BeTrue();
    }

    [Fact]
    public async Task Summary_EmptyOrUnknownIds_ReturnsEmptyList()
    {
        var resp = await SummaryAsync(Guid.NewGuid().ToString());

        resp.StatusCode.Should().Be(HttpStatusCode.OK);
        (await resp.Content.ReadFromJsonAsync<List<SummaryResponse>>()).Should().BeEmpty();
    }

    [Fact]
    public async Task Summary_TooManyIds_Returns400()
    {
        var ids = Enumerable.Range(0, 501).Select(_ => Guid.NewGuid().ToString()).ToArray();

        (await SummaryAsync(ids)).StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Summary_WithNoToken_Returns401()
    {
        using var anon = _factory.CreateClient();
        var resp = await anon.PostAsJsonAsync("/api/media/progress-summary", new { ids = new[] { "x" } });

        resp.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    private record LibraryResponse(string Id);

    private record SummaryResponse(string MediaId, double Progress, bool IsCompleted, int NewCount, bool IsNew);
}
