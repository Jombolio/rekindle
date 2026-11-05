using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text;
using System.Text.Json;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.Tokens;
using Rekindle.Core.Models;
using Rekindle.Core.Repositories;
using Rekindle.Tests.Helpers;
using Xunit;

namespace Rekindle.Tests.Integration;

public class BookEndpointTests : IClassFixture<TestWebApplicationFactory>, IDisposable
{
    private readonly string _dir = Path.Combine(Path.GetTempPath(), $"rekindle-books-{Guid.NewGuid():N}");
    private readonly HttpClient _client;
    private readonly TestWebApplicationFactory _factory;

    public BookEndpointTests(TestWebApplicationFactory factory)
    {
        Directory.CreateDirectory(_dir);
        _factory = factory;
        _client = factory.CreateClient();
        _client.SetBearerToken(factory.AdminToken);
    }

    public void Dispose() => TempCleanup.DeleteDirectory(_dir);

    private async Task<string> SeedAsync(string filePath, string format)
    {
        var libraries = _factory.Services.GetRequiredService<LibraryRepository>();
        var media = _factory.Services.GetRequiredService<MediaRepository>();

        var libraryId = Guid.NewGuid().ToString();
        await libraries.InsertAsync(new Library { Id = libraryId, Name = libraryId, RootPath = _dir, Type = "book" });
        var id = Guid.NewGuid().ToString();
        await media.InsertAsync(new Media { Id = id, LibraryId = libraryId, Title = "Book", FilePath = filePath, Format = format });
        return id;
    }

    private string Epub(params string[] chapters)
    {
        var path = Path.Combine(_dir, $"{Guid.NewGuid():N}.epub");
        BookFixtures.WriteEpub(path, chapters);
        return path;
    }

    private string Mobi(BookFixtures.Mobi mobi)
    {
        var path = Path.Combine(_dir, $"{Guid.NewGuid():N}.mobi");
        File.WriteAllBytes(path, mobi.Build());
        return path;
    }

    [Fact]
    public async Task PageCount_ForAnEpub_CountsChaptersNotImages()
    {
        // The fixture has 3 chapters and an image: the image count used to be
        // returned here, and clients treated it as the book's length.
        var id = await SeedAsync(Epub("a.xhtml", "b.xhtml", "c.xhtml"), "epub");

        var resp = await _client.GetAsync($"/api/media/{id}/pagecount");

        resp.StatusCode.Should().Be(HttpStatusCode.OK);
        var body = await resp.Content.ReadFromJsonAsync<JsonElement>();
        body.GetProperty("pageCount").GetInt32().Should().Be(3);

        var stored = await _factory.Services.GetRequiredService<MediaRepository>().GetByIdAsync(id);
        stored!.PageCount.Should().Be(3);
    }

    [Fact]
    public async Task Book_ForAnEpub_ReturnsTheFile()
    {
        var path = Epub("a.xhtml");
        var id = await SeedAsync(path, "epub");

        var resp = await _client.GetAsync($"/api/media/{id}/book");

        resp.StatusCode.Should().Be(HttpStatusCode.OK);
        resp.Content.Headers.ContentType!.MediaType.Should().Be("application/epub+zip");
        (await resp.Content.ReadAsByteArrayAsync()).Should().Equal(File.ReadAllBytes(path));
    }

    [Fact]
    public async Task Book_ForAMobi_ReturnsAnEpub()
    {
        var id = await SeedAsync(Mobi(new BookFixtures.Mobi { Text = "<p>hi</p>"u8.ToArray() }), "mobi");

        var resp = await _client.GetAsync($"/api/media/{id}/book");

        resp.StatusCode.Should().Be(HttpStatusCode.OK);
        var bytes = await resp.Content.ReadAsByteArrayAsync();
        bytes[..2].Should().Equal((byte)'P', (byte)'K');

        var count = await _client.GetFromJsonAsync<JsonElement>($"/api/media/{id}/pagecount");
        count.GetProperty("pageCount").GetInt32().Should().Be(1);
    }

    [Fact]
    public async Task Book_ForAnUnconvertibleMobi_Returns422WithTheReason()
    {
        var id = await SeedAsync(Mobi(new BookFixtures.Mobi { Text = "<p>a</p>"u8.ToArray(), Encryption = 2 }), "mobi");

        var resp = await _client.GetAsync($"/api/media/{id}/book");

        resp.StatusCode.Should().Be(HttpStatusCode.UnprocessableEntity);
        var body = await resp.Content.ReadFromJsonAsync<JsonElement>();
        body.GetProperty("error").GetString().Should().Contain("DRM");
    }

    [Fact]
    public async Task Book_ForAComic_Returns404()
    {
        var id = await SeedAsync(Path.Combine(_dir, "comic.cbz"), "cbz");
        (await _client.GetAsync($"/api/media/{id}/book")).StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task Book_ForAReadOnlyAccount_Returns403()
    {
        var id = await SeedAsync(Epub("a.xhtml"), "epub");
        using var readOnly = _factory.CreateClient();
        readOnly.SetBearerToken(await TokenAtLevelAsync(1));

        (await readOnly.GetAsync($"/api/media/{id}/book")).StatusCode.Should().Be(HttpStatusCode.Forbidden);
        // Still allowed: the same account can see how long the book is.
        (await readOnly.GetAsync($"/api/media/{id}/pagecount")).StatusCode.Should().Be(HttpStatusCode.OK);
    }

    [Fact]
    public async Task Book_ForADownloadAccount_ReturnsTheBook()
    {
        var id = await SeedAsync(Epub("a.xhtml"), "epub");
        using var downloader = _factory.CreateClient();
        downloader.SetBearerToken(await TokenAtLevelAsync(2));

        (await downloader.GetAsync($"/api/media/{id}/book")).StatusCode.Should().Be(HttpStatusCode.OK);
    }

    /// A token for a real user at this permission level.
    private async Task<string> TokenAtLevelAsync(int level)
    {
        var id = Guid.NewGuid().ToString();
        await _factory.Services.GetRequiredService<UserRepository>().InsertAsync(
            new User { Id = id, Username = id, PasswordHash = "x:y", PermissionLevel = level });

        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes("integration-test-secret-key-min-32-chars!!"));
        var token = new JwtSecurityToken(
            issuer: "Rekindle",
            audience: "Rekindle",
            claims:
            [
                new Claim(JwtRegisteredClaimNames.Sub, id),
                new Claim(JwtRegisteredClaimNames.UniqueName, id),
                new Claim("permission_level", level.ToString()),
                new Claim(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString()),
            ],
            expires: DateTime.UtcNow.AddHours(1),
            signingCredentials: new SigningCredentials(key, SecurityAlgorithms.HmacSha256));
        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    [Fact]
    public async Task Book_WithoutSigningIn_Returns401()
    {
        using var anonymous = _factory.CreateClient();
        (await anonymous.GetAsync($"/api/media/{Guid.NewGuid()}/book")).StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task Progress_KeepsThePositionWithinTheChapter()
    {
        var id = await SeedAsync(Epub("a.xhtml", "b.xhtml"), "epub");

        var post = await _client.PostAsJsonAsync($"/api/media/{id}/progress",
            new { currentPage = 1, isCompleted = false, positionFraction = 0.4, lastReadAt = DateTime.UtcNow.AddSeconds(-1) });
        post.StatusCode.Should().Be(HttpStatusCode.OK);

        var body = await _client.GetFromJsonAsync<JsonElement>($"/api/media/{id}/progress");
        body.GetProperty("currentPage").GetInt32().Should().Be(1);
        body.GetProperty("positionFraction").GetDouble().Should().BeApproximately(0.4, 0.0001);
    }

    [Fact]
    public async Task Progress_OutOfRangePosition_IsClamped()
    {
        var id = await SeedAsync(Epub("a.xhtml"), "epub");

        await _client.PostAsJsonAsync($"/api/media/{id}/progress",
            new { currentPage = 0, isCompleted = false, positionFraction = 7.5, lastReadAt = DateTime.UtcNow.AddSeconds(-1) });

        var body = await _client.GetFromJsonAsync<JsonElement>($"/api/media/{id}/progress");
        body.GetProperty("positionFraction").GetDouble().Should().Be(1);
    }
}
