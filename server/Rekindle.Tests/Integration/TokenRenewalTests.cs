using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text;
using FluentAssertions;
using Microsoft.IdentityModel.Tokens;
using Rekindle.Server.Authorization;
using Rekindle.Tests.Helpers;
using Xunit;

namespace Rekindle.Tests.Integration;

public class TokenRenewalTests : IClassFixture<TestWebApplicationFactory>
{
    // Matches TestWebApplicationFactory's configured Jwt:Secret.
    private const string Secret = "integration-test-secret-key-min-32-chars!!";

    private readonly TestWebApplicationFactory factory;

    public TokenRenewalTests(TestWebApplicationFactory factory) => this.factory = factory;

    [Fact]
    public async Task FreshToken_IsNotRenewed()
    {
        var client = factory.CreateClient();
        client.SetBearerToken(factory.AdminToken);

        var resp = await client.GetAsync("/api/auth/me");

        resp.StatusCode.Should().Be(HttpStatusCode.OK);
        resp.Headers.Contains(TokenRenewal.HeaderName).Should().BeFalse();
        var body = await resp.Content.ReadFromJsonAsync<MeResponse>();
        body!.Token.Should().BeNull();
    }

    [Fact]
    public async Task TokenNearingExpiry_IsReplacedOnAnyAuthenticatedRequest()
    {
        var client = factory.CreateClient();
        var me = await GetMeAsync(client, factory.AdminToken);

        var expiring = MintToken(me.Id, me.PermissionLevel, TimeSpan.FromMinutes(1));
        client.SetBearerToken(expiring);

        // Renewal rides on ordinary traffic, not just /api/auth/me — that is what
        // keeps a long-running session alive without any client-side polling.
        var resp = await client.GetAsync("/api/libraries");

        resp.StatusCode.Should().Be(HttpStatusCode.OK);
        resp.Headers.TryGetValues(TokenRenewal.HeaderName, out var values).Should().BeTrue();
        var renewed = values!.Single();
        renewed.Should().NotBe(expiring);

        // The replacement must actually authenticate, with a full-length lifetime.
        client.SetBearerToken(renewed);
        (await client.GetAsync("/api/auth/me")).StatusCode.Should().Be(HttpStatusCode.OK);
        new JwtSecurityTokenHandler().ReadJwtToken(renewed)
            .ValidTo.Should().BeAfter(DateTime.UtcNow.AddDays(20));
    }

    [Fact]
    public async Task Me_EchoesTheReplacementTokenInTheBody()
    {
        var client = factory.CreateClient();
        var me = await GetMeAsync(client, factory.AdminToken);

        var body = await GetMeAsync(client, MintToken(me.Id, me.PermissionLevel, TimeSpan.FromMinutes(1)));

        body.Token.Should().NotBeNullOrEmpty();
    }

    private static async Task<MeResponse> GetMeAsync(HttpClient client, string token)
    {
        client.SetBearerToken(token);
        var resp = await client.GetAsync("/api/auth/me");
        resp.EnsureSuccessStatusCode();
        return (await resp.Content.ReadFromJsonAsync<MeResponse>())!;
    }

    /// Mints a token the server still accepts but considers close enough to expiry
    /// to replace — the state a client reaches after running for weeks.
    private static string MintToken(string userId, int permissionLevel, TimeSpan remaining)
    {
        var creds = new SigningCredentials(
            new SymmetricSecurityKey(Encoding.UTF8.GetBytes(Secret)),
            SecurityAlgorithms.HmacSha256);

        var token = new JwtSecurityToken(
            issuer: "Rekindle",
            audience: "Rekindle",
            claims:
            [
                new Claim(JwtRegisteredClaimNames.Sub, userId),
                new Claim(JwtRegisteredClaimNames.UniqueName, TestWebApplicationFactory.AdminUsername),
                new Claim("permission_level", permissionLevel.ToString()),
                new Claim(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString()),
            ],
            expires: DateTime.UtcNow.Add(remaining),
            signingCredentials: creds);

        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    private record MeResponse(string Id, string Username, int PermissionLevel, string? Token);
}
