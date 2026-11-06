using System.Net;
using System.Net.Http.Json;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using Rekindle.Core.Models;
using Rekindle.Core.Repositories;
using Rekindle.Tests.Helpers;
using Xunit;

namespace Rekindle.Tests.Integration;

public class ReadMarkEndpointTests : IClassFixture<TestWebApplicationFactory>
{
    private readonly HttpClient _client;
    private readonly TestWebApplicationFactory _factory;

    public ReadMarkEndpointTests(TestWebApplicationFactory factory)
    {
        _factory = factory;
        _client = factory.CreateClient();
        _client.SetBearerToken(factory.AdminToken);
    }

    [Fact]
    public async Task Marking_a_chapter_read_keeps_its_progress()
    {
        var lib = await CreateLibraryAsync();
        var chapter = await InsertAsync(lib, "archive", null, pages: 40);
        var reader = await ClientAtLevelAsync(1);
        (await reader.PostAsJsonAsync($"/api/media/{chapter.Id}/progress",
            new { currentPage = 12, isCompleted = false, lastReadAt = DateTime.UtcNow.AddSeconds(-1) }))
            .EnsureSuccessStatusCode();

        (await reader.PutAsync($"/api/media/{chapter.Id}/read-mark", null)).StatusCode.Should().Be(HttpStatusCode.OK);

        var summary = await SummaryAsync(reader, chapter.Id);
        summary.IsCompleted.Should().BeTrue();
        summary.MarkedRead.Should().BeTrue();
        var progress = await reader.GetFromJsonAsync<ProgressBody>($"/api/media/{chapter.Id}/progress");
        progress!.CurrentPage.Should().Be(12);
        progress.IsCompleted.Should().BeFalse();

        // Rereading from the start doesn't unmark it.
        (await reader.PostAsJsonAsync($"/api/media/{chapter.Id}/progress",
            new { currentPage = 0, isCompleted = false, lastReadAt = DateTime.UtcNow }))
            .EnsureSuccessStatusCode();
        (await SummaryAsync(reader, chapter.Id)).IsCompleted.Should().BeTrue();

        (await reader.DeleteAsync($"/api/media/{chapter.Id}/read-mark")).StatusCode.Should().Be(HttpStatusCode.OK);
        var after = await SummaryAsync(reader, chapter.Id);
        after.IsCompleted.Should().BeFalse();
        after.MarkedRead.Should().BeFalse();
    }

    [Fact]
    public async Task Marking_a_series_marks_every_chapter_in_it()
    {
        var lib = await CreateLibraryAsync();
        var series = await InsertAsync(lib, "folder", null, pages: null);
        var volume = await InsertAsync(lib, "folder", series.Id, pages: null);
        var c1 = await InsertAsync(lib, "archive", series.Id, pages: 10);
        var c2 = await InsertAsync(lib, "archive", volume.Id, pages: 10);

        var resp = await _client.PutAsync($"/api/media/{series.Id}/read-mark", null);
        (await resp.Content.ReadFromJsonAsync<MarkBody>())!.Chapters.Should().Be(2);

        (await SummaryAsync(_client, series.Id)).MarkedRead.Should().BeTrue();
        (await SummaryAsync(_client, c2.Id)).MarkedRead.Should().BeTrue();

        await _client.DeleteAsync($"/api/media/{series.Id}/read-mark");
        (await SummaryAsync(_client, c1.Id)).MarkedRead.Should().BeFalse();
    }

    [Fact]
    public async Task Marks_are_each_users_own()
    {
        var lib = await CreateLibraryAsync();
        var chapter = await InsertAsync(lib, "archive", null, pages: 10);
        var someone = await ClientAtLevelAsync(1);

        await _client.PutAsync($"/api/media/{chapter.Id}/read-mark", null);

        (await SummaryAsync(_client, chapter.Id)).MarkedRead.Should().BeTrue();
        (await SummaryAsync(someone, chapter.Id)).MarkedRead.Should().BeFalse();
    }

    [Fact]
    public async Task Ignoring_an_annual_lets_the_series_count_as_finished()
    {
        var lib = await CreateLibraryAsync();
        var series = await InsertAsync(lib, "folder", null, pages: null);
        var issue = await InsertAsync(lib, "archive", series.Id, pages: 10);
        var annual = await InsertAsync(lib, "archive", series.Id, pages: 40);
        var reader = await ClientAtLevelAsync(1);
        await reader.PostAsJsonAsync($"/api/media/{issue.Id}/progress",
            new { currentPage = 9, isCompleted = true, lastReadAt = DateTime.UtcNow.AddSeconds(-2) });
        await reader.PostAsJsonAsync($"/api/media/{annual.Id}/progress",
            new { currentPage = 4, isCompleted = false, lastReadAt = DateTime.UtcNow.AddSeconds(-1) });
        (await SummaryAsync(reader, series.Id)).IsCompleted.Should().BeFalse();

        (await reader.PutAsync($"/api/media/{annual.Id}/tracking-ignore", null)).StatusCode.Should().Be(HttpStatusCode.OK);

        (await SummaryAsync(reader, series.Id)).IsCompleted.Should().BeTrue();
        var annualSummary = await SummaryAsync(reader, annual.Id);
        annualSummary.Ignored.Should().BeTrue();
        // Its own progress is kept.
        (await reader.GetFromJsonAsync<ProgressBody>($"/api/media/{annual.Id}/progress"))!.CurrentPage.Should().Be(4);

        (await reader.DeleteAsync($"/api/media/{annual.Id}/tracking-ignore")).StatusCode.Should().Be(HttpStatusCode.OK);
        (await SummaryAsync(reader, series.Id)).IsCompleted.Should().BeFalse();
        (await SummaryAsync(reader, annual.Id)).Ignored.Should().BeFalse();
    }

    [Fact]
    public async Task Unknown_media_is_not_found_and_anonymous_is_refused()
    {
        (await _client.PutAsync("/api/media/nope/read-mark", null)).StatusCode.Should().Be(HttpStatusCode.NotFound);
        using var anon = _factory.CreateClient();
        (await anon.PutAsync("/api/media/nope/read-mark", null)).StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    private async Task<SummaryBody> SummaryAsync(HttpClient client, string id)
    {
        var resp = await client.PostAsJsonAsync("/api/media/progress-summary", new { ids = new[] { id } });
        resp.EnsureSuccessStatusCode();
        return (await resp.Content.ReadFromJsonAsync<List<SummaryBody>>())!.Single();
    }

    private async Task<string> CreateLibraryAsync()
    {
        var root = Path.Combine(Path.GetTempPath(), $"rekindle-marks-{Guid.NewGuid():N}");
        Directory.CreateDirectory(root);
        var resp = await _client.PostAsJsonAsync("/api/libraries", new { name = "Marks", rootPath = root, type = "manga" });
        resp.EnsureSuccessStatusCode();
        return (await resp.Content.ReadFromJsonAsync<IdBody>())!.Id;
    }

    private async Task<Media> InsertAsync(string libraryId, string type, string? parentId, int? pages)
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
            AddedAt = DateTime.UtcNow.AddDays(-1),
        };
        using var scope = _factory.Services.CreateScope();
        await scope.ServiceProvider.GetRequiredService<MediaRepository>().InsertAsync(media);
        return media;
    }

    private async Task<HttpClient> ClientAtLevelAsync(int level)
    {
        var username = $"user{Guid.NewGuid():N}";
        const string password = "Password123!";
        (await _client.PostAsJsonAsync("/api/users", new { username, password, permissionLevel = level }))
            .EnsureSuccessStatusCode();
        var client = _factory.CreateClient();
        client.SetBearerToken(await AuthHelper.LoginAsync(client, username, password));
        return client;
    }

    private record IdBody(string Id);
    private record MarkBody(bool MarkedRead, int Chapters);
    private record ProgressBody(int CurrentPage, bool IsCompleted);
    private record SummaryBody(string MediaId, double Progress, bool IsCompleted, bool MarkedRead, bool Ignored);
}
