using System.Net;
using System.Net.Http.Json;
using FluentAssertions;
using Rekindle.Tests.Helpers;
using Xunit;

namespace Rekindle.Tests.Integration;

public class LibrariesControllerTests : IClassFixture<TestWebApplicationFactory>
{
    private readonly HttpClient _client;
    private readonly TestWebApplicationFactory _factory;

    public LibrariesControllerTests(TestWebApplicationFactory factory)
    {
        _factory = factory;
        _client = factory.CreateClient();
        _client.SetBearerToken(factory.AdminToken);
    }

    [Fact]
    public async Task GetAll_WithNoToken_Returns401()
    {
        // Use a factory client without a token set
        using var anonClient = _factory.CreateClient();
        var resp = await anonClient.GetAsync("/api/libraries");
        resp.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task GetAll_Authenticated_ReturnsOk()
    {
        var resp = await _client.GetAsync("/api/libraries");
        resp.StatusCode.Should().Be(HttpStatusCode.OK);
    }

    [Fact]
    public async Task Create_AsAdmin_WithValidPath_Returns201()
    {
        var resp = await _client.PostAsJsonAsync("/api/libraries", new
        {
            name = "Test Comics",
            rootPath = Path.GetTempPath(),
            type = "comic"
        });

        resp.StatusCode.Should().Be(HttpStatusCode.Created);
        var body = await resp.Content.ReadFromJsonAsync<LibraryResponse>();
        body!.Name.Should().Be("Test Comics");
        body.Type.Should().Be("comic");
    }

    [Fact]
    public async Task Create_WithNonExistentPath_Returns400()
    {
        var resp = await _client.PostAsJsonAsync("/api/libraries", new
        {
            name = "Bad Library",
            rootPath = "/this/path/does/not/exist",
            type = "comic"
        });

        resp.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Create_WithInvalidType_Returns400()
    {
        var resp = await _client.PostAsJsonAsync("/api/libraries", new
        {
            name = "Bad Library",
            rootPath = Path.GetTempPath(),
            type = "invalid-type"
        });

        resp.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Delete_ExistingLibrary_Returns204()
    {
        var createResp = await _client.PostAsJsonAsync("/api/libraries", new
        {
            name = "To Delete",
            rootPath = Path.GetTempPath(),
            type = "book"
        });
        var lib = await createResp.Content.ReadFromJsonAsync<LibraryResponse>();

        var deleteResp = await _client.DeleteAsync($"/api/libraries/{lib!.Id}");

        deleteResp.StatusCode.Should().Be(HttpStatusCode.NoContent);
    }

    [Fact]
    public async Task Scan_ExistingLibrary_Returns202()
    {
        var createResp = await _client.PostAsJsonAsync("/api/libraries", new
        {
            name = "Scannable",
            rootPath = Path.GetTempPath(),
            type = "manga"
        });
        var lib = await createResp.Content.ReadFromJsonAsync<LibraryResponse>();

        var scanResp = await _client.PostAsync($"/api/libraries/{lib!.Id}/scan", null);

        scanResp.StatusCode.Should().Be(HttpStatusCode.Accepted);
    }

    [Fact]
    public async Task Delete_NonExistentLibrary_Returns404()
    {
        var resp = await _client.DeleteAsync($"/api/libraries/{Guid.NewGuid()}");
        resp.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    private record LibraryResponse(string Id, string Name, string RootPath, string Type);
}
