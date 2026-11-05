using System.Net;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using Rekindle.Core.Models;
using Rekindle.Core.Repositories;
using Rekindle.Core.Services;
using Rekindle.Tests.Helpers;
using Xunit;

namespace Rekindle.Tests.Integration;

public class BookImportEndpointTests : IClassFixture<TestWebApplicationFactory>, IDisposable
{
    private readonly string _dir = Path.Combine(Path.GetTempPath(), $"rekindle-import-{Guid.NewGuid():N}");
    private readonly HttpClient _client;
    private readonly TestWebApplicationFactory _factory;

    public BookImportEndpointTests(TestWebApplicationFactory factory)
    {
        Directory.CreateDirectory(_dir);
        _factory = factory;
        _client = factory.CreateClient();
        _client.SetBearerToken(factory.AdminToken);
    }

    public void Dispose() => TempCleanup.DeleteDirectory(_dir);

    private async Task<string> LibraryAsync()
    {
        var id = Guid.NewGuid().ToString();
        await _factory.Services.GetRequiredService<LibraryRepository>()
            .InsertAsync(new Library { Id = id, Name = id, RootPath = _dir, Type = "book" });
        return id;
    }

    private static MultipartFormDataContent InspectForm(string libraryId, string fileName, byte[]? head, string? title = null)
    {
        var form = new MultipartFormDataContent
        {
            { new StringContent(libraryId), "libraryId" },
            { new StringContent(fileName), "fileName" },
        };
        if (title is not null) form.Add(new StringContent(title), "title");
        if (head is not null) form.Add(new ByteArrayContent(head), "head", "head");
        return form;
    }

    private static MultipartFormDataContent UploadForm(string libraryId, string fileName, byte[] data, bool deferScan)
    {
        var form = new MultipartFormDataContent
        {
            { new StringContent(libraryId), "libraryId" },
            { new ByteArrayContent(data), "file", fileName },
        };
        if (deferScan) form.Add(new StringContent("true"), "deferScan");
        return form;
    }

    private async Task<HttpClient> ClientAtLevelAsync(int level)
    {
        var username = $"user{Guid.NewGuid():N}";
        const string password = "Password123!";
        var created = await _client.PostAsJsonAsync("/api/users", new { username, password, permissionLevel = level });
        created.EnsureSuccessStatusCode();

        var client = _factory.CreateClient();
        client.SetBearerToken(await AuthHelper.LoginAsync(client, username, password));
        return client;
    }

    private static byte[] Mobi(int encryption = 0) => new BookFixtures.Mobi
    {
        Text = Encoding.UTF8.GetBytes("<p>hello</p>"),
        Encryption = encryption,
        Title = "A Book",
        Author = "An Author",
    }.Build();

    [Fact]
    public async Task Inspect_ReportsTitleAuthorAndStatus()
    {
        var resp = await _client.PostAsync("/api/admin/upload/inspect", InspectForm(await LibraryAsync(), "a.mobi", Mobi()));

        resp.StatusCode.Should().Be(HttpStatusCode.OK);
        var body = await resp.Content.ReadFromJsonAsync<JsonElement>();
        body.GetProperty("status").GetString().Should().Be("Ready");
        body.GetProperty("title").GetString().Should().Be("A Book");
        body.GetProperty("author").GetString().Should().Be("An Author");
    }

    [Fact]
    public async Task Inspect_ReportsDrm_AndWritesNothingToTheLibrary()
    {
        var resp = await _client.PostAsync("/api/admin/upload/inspect", InspectForm(await LibraryAsync(), "a.azw3", Mobi(encryption: 2)));

        var body = await resp.Content.ReadFromJsonAsync<JsonElement>();
        body.GetProperty("status").GetString().Should().Be("DrmProtected");
        body.GetProperty("reason").GetString().Should().Be(BookImportInspector.DrmReason);
        Directory.EnumerateFileSystemEntries(_dir).Should().BeEmpty();
    }

    [Fact]
    public async Task Inspect_ReportsKfx_WithoutAHead()
    {
        var resp = await _client.PostAsync("/api/admin/upload/inspect", InspectForm(await LibraryAsync(), "a.kfx", null));

        var body = await resp.Content.ReadFromJsonAsync<JsonElement>();
        body.GetProperty("status").GetString().Should().Be("UnsupportedFormat");
    }

    [Fact]
    public async Task Inspect_FindsBooksTheLibraryHasAlready_InAnyFolder()
    {
        var libraryId = await LibraryAsync();
        await _factory.Services.GetRequiredService<MediaRepository>().InsertAsync(new Media
        {
            LibraryId = libraryId,
            Title = "A Book",
            FilePath = Path.Combine(_dir, "nested", "folder", "something.epub"),
            Format = "epub",
        });

        var resp = await _client.PostAsync("/api/admin/upload/inspect", InspectForm(libraryId, "other.mobi", Mobi()));

        var body = await resp.Content.ReadFromJsonAsync<JsonElement>();
        body.GetProperty("status").GetString().Should().Be("AlreadyInLibrary");
    }

    [Fact]
    public async Task Inspect_OnlyLooksInTheChosenLibrary()
    {
        var other = await LibraryAsync();
        await _factory.Services.GetRequiredService<MediaRepository>().InsertAsync(new Media
        {
            LibraryId = other,
            Title = "A Book",
            FilePath = Path.Combine(_dir, "a.mobi"),
            Format = "mobi",
        });

        var resp = await _client.PostAsync("/api/admin/upload/inspect", InspectForm(await LibraryAsync(), "a.mobi", Mobi()));

        var body = await resp.Content.ReadFromJsonAsync<JsonElement>();
        body.GetProperty("status").GetString().Should().Be("Ready");
    }

    [Fact]
    public async Task Inspect_ForAnUnknownLibrary_Returns404()
    {
        var resp = await _client.PostAsync("/api/admin/upload/inspect", InspectForm("nope", "a.mobi", Mobi()));

        resp.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task Inspect_IsOpenToLevel3()
    {
        var client = await ClientAtLevelAsync(3);

        var resp = await client.PostAsync("/api/admin/upload/inspect", InspectForm(await LibraryAsync(), "a.mobi", Mobi()));

        resp.StatusCode.Should().Be(HttpStatusCode.OK);
    }

    [Fact]
    public async Task Inspect_IsClosedToLevel2()
    {
        var client = await ClientAtLevelAsync(2);

        var resp = await client.PostAsync("/api/admin/upload/inspect", InspectForm(await LibraryAsync(), "a.mobi", Mobi()));

        resp.StatusCode.Should().Be(HttpStatusCode.Forbidden);
    }

    [Fact]
    public async Task Upload_WithDeferredScan_LeavesTheScanToTheCaller()
    {
        var libraryId = await LibraryAsync();
        var tracker = _factory.Services.GetRequiredService<ScanProgressTracker>();

        var first = await _client.PostAsync("/api/admin/upload", UploadForm(libraryId, "one.mobi", Mobi(), deferScan: true));
        var second = await _client.PostAsync("/api/admin/upload", UploadForm(libraryId, "two.mobi", Mobi(), deferScan: true));

        first.StatusCode.Should().Be(HttpStatusCode.OK);
        second.StatusCode.Should().Be(HttpStatusCode.OK);
        File.Exists(Path.Combine(_dir, "one.mobi")).Should().BeTrue();
        File.Exists(Path.Combine(_dir, "two.mobi")).Should().BeTrue();

        await Task.Delay(200, TestContext.Current.CancellationToken);
        tracker.Get(libraryId).Should().BeNull();

        var scan = await _client.PostAsync($"/api/libraries/{libraryId}/scan", null);
        scan.StatusCode.Should().Be(HttpStatusCode.Accepted);
        (await scan.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("started").GetBoolean().Should().BeTrue();

        var media = _factory.Services.GetRequiredService<MediaRepository>();
        for (var i = 0; i < 100 && (await media.GetBookNamesForLibraryAsync(libraryId)).Count < 2; i++)
            await Task.Delay(50, TestContext.Current.CancellationToken);
        var names = await media.GetBookNamesForLibraryAsync(libraryId);
        names.Select(n => n.FileName).Should().BeEquivalentTo("one.mobi", "two.mobi");
    }

    [Fact]
    public async Task Upload_WithoutDeferring_StillStartsAScan()
    {
        var libraryId = await LibraryAsync();
        var tracker = _factory.Services.GetRequiredService<ScanProgressTracker>();

        var resp = await _client.PostAsync("/api/admin/upload", UploadForm(libraryId, "one.mobi", Mobi(), deferScan: false));

        resp.StatusCode.Should().Be(HttpStatusCode.OK);
        for (var i = 0; i < 100 && tracker.Get(libraryId) is null; i++)
            await Task.Delay(50, TestContext.Current.CancellationToken);
        tracker.Get(libraryId).Should().NotBeNull();
    }

    [Fact]
    public async Task Upload_OfAFileThatExists_Returns409()
    {
        var libraryId = await LibraryAsync();
        await File.WriteAllBytesAsync(Path.Combine(_dir, "one.mobi"), Mobi(), TestContext.Current.CancellationToken);

        var resp = await _client.PostAsync("/api/admin/upload", UploadForm(libraryId, "one.mobi", Mobi(), deferScan: true));

        resp.StatusCode.Should().Be(HttpStatusCode.Conflict);
    }

    [Fact]
    public async Task Upload_OfKfx_IsRejected()
    {
        var resp = await _client.PostAsync("/api/admin/upload", UploadForm(await LibraryAsync(), "one.kfx", [1, 2, 3], deferScan: true));

        resp.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        File.Exists(Path.Combine(_dir, "one.kfx")).Should().BeFalse();
    }
}
