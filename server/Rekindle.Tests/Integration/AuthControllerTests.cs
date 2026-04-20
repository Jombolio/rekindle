using System.Net;
using System.Net.Http.Json;
using FluentAssertions;
using Rekindle.Tests.Helpers;
using Xunit;

namespace Rekindle.Tests.Integration;

public class AuthControllerTests : IClassFixture<TestWebApplicationFactory>
{
    private readonly HttpClient _client;
    private readonly TestWebApplicationFactory _factory;

    public AuthControllerTests(TestWebApplicationFactory factory)
    {
        _factory = factory;
        _client = factory.CreateClient();
    }

    [Fact]
    public async Task Setup_WhenAdminAlreadyExists_Returns409()
    {
        // Factory pre-seeds admin on init — setup is always blocked here
        var resp = await _client.PostAsJsonAsync("/api/auth/setup", new
        {
            username = "another-admin",
            password = "Pass1!"
        });

        resp.StatusCode.Should().Be(HttpStatusCode.Conflict);
    }

    [Fact]
    public async Task Login_WithValidCredentials_ReturnsToken()
    {
        var resp = await _client.PostAsJsonAsync("/api/auth/login", new
        {
            username = TestWebApplicationFactory.AdminUsername,
            password = TestWebApplicationFactory.AdminPassword
        });

        resp.StatusCode.Should().Be(HttpStatusCode.OK);
        var body = await resp.Content.ReadFromJsonAsync<TokenResponse>();
        body!.Token.Should().NotBeNullOrEmpty();
    }

    [Fact]
    public async Task Login_WithWrongPassword_Returns401()
    {
        var resp = await _client.PostAsJsonAsync("/api/auth/login", new
        {
            username = TestWebApplicationFactory.AdminUsername,
            password = "WrongPassword!"
        });

        resp.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task Login_WithUnknownUser_Returns401()
    {
        var resp = await _client.PostAsJsonAsync("/api/auth/login", new
        {
            username = "nobody",
            password = "irrelevant"
        });

        resp.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task Me_WithNoToken_Returns401()
    {
        var resp = await _client.GetAsync("/api/auth/me");

        resp.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task Me_WithValidToken_ReturnsUserProfile()
    {
        _client.SetBearerToken(_factory.AdminToken);

        var resp = await _client.GetAsync("/api/auth/me");

        resp.StatusCode.Should().Be(HttpStatusCode.OK);
        var body = await resp.Content.ReadFromJsonAsync<MeResponse>();
        body!.Username.Should().Be(TestWebApplicationFactory.AdminUsername);
        body.PermissionLevel.Should().Be(4);
    }

    [Fact]
    public async Task Me_WithExpiredOrInvalidToken_Returns401()
    {
        _client.SetBearerToken("this.is.not.a.valid.jwt");

        var resp = await _client.GetAsync("/api/auth/me");

        resp.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    private record TokenResponse(string Token);
    private record MeResponse(string Id, string Username, int PermissionLevel);
}
