using System.Net;
using System.Net.Http.Json;
using FluentAssertions;
using Rekindle.Tests.Helpers;
using Xunit;

namespace Rekindle.Tests.Integration;

public class MediaControllerTests : IClassFixture<TestWebApplicationFactory>
{
    private readonly HttpClient _client;
    private readonly TestWebApplicationFactory _factory;

    public MediaControllerTests(TestWebApplicationFactory factory)
    {
        _factory = factory;
        _client = factory.CreateClient();
        _client.SetBearerToken(factory.AdminToken);
    }

    [Fact]
    public async Task GetPaged_WithNoToken_Returns401()
    {
        using var anonClient = _factory.CreateClient();
        var resp = await anonClient.GetAsync("/api/media?libraryId=any");
        resp.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task GetPaged_WithNoLibraryId_Returns400()
    {
        var resp = await _client.GetAsync("/api/media");
        resp.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task GetPaged_WithValidLibraryId_ReturnsPagedResult()
    {
        var createResp = await _client.PostAsJsonAsync("/api/libraries", new
        {
            name = "Media Test Comics",
            rootPath = Path.GetTempPath(),
            type = "comic"
        });
        var lib = await createResp.Content.ReadFromJsonAsync<LibraryResponse>();

        var resp = await _client.GetAsync($"/api/media?libraryId={lib!.Id}");

        resp.StatusCode.Should().Be(HttpStatusCode.OK);
        var body = await resp.Content.ReadFromJsonAsync<PagedResponse>();
        body!.Total.Should().Be(0);
        body.Page.Should().Be(1);
    }

    [Fact]
    public async Task GetById_NonExistentMedia_Returns404()
    {
        var resp = await _client.GetAsync($"/api/media/{Guid.NewGuid()}");
        resp.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task GetProgress_NeverReadMedia_ReturnsDefaultZeroProgress()
    {
        // Progress endpoint returns defaults rather than 404 — client just hasn't opened it yet
        var resp = await _client.GetAsync($"/api/media/{Guid.NewGuid()}/progress");
        resp.StatusCode.Should().Be(HttpStatusCode.OK);
        var body = await resp.Content.ReadFromJsonAsync<ProgressResponse>();
        body!.CurrentPage.Should().Be(0);
        body.IsCompleted.Should().BeFalse();
    }

    [Fact]
    public async Task Download_NonExistentMedia_Returns404()
    {
        var resp = await _client.GetAsync($"/api/media/{Guid.NewGuid()}/download");
        resp.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task GetPage_NonExistentMedia_Returns404()
    {
        var resp = await _client.GetAsync($"/api/media/{Guid.NewGuid()}/page/0");
        resp.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task GetPaged_PageSizeIsClamped()
    {
        var createResp = await _client.PostAsJsonAsync("/api/libraries", new
        {
            name = "Clamp Test",
            rootPath = Path.GetTempPath(),
            type = "book"
        });
        var lib = await createResp.Content.ReadFromJsonAsync<LibraryResponse>();

        var resp = await _client.GetAsync($"/api/media?libraryId={lib!.Id}&pageSize=9999");

        resp.StatusCode.Should().Be(HttpStatusCode.OK);
        var body = await resp.Content.ReadFromJsonAsync<PagedResponse>();
        body!.PageSize.Should().Be(200);
    }

    private record LibraryResponse(string Id, string Name, string RootPath, string Type);
    private record PagedResponse(int Total, int Page, int PageSize, int TotalPages);
    private record ProgressResponse(int CurrentPage, bool IsCompleted);
}
