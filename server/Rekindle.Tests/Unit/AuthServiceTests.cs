using System.IdentityModel.Tokens.Jwt;
using FluentAssertions;
using Xunit;
using Microsoft.Extensions.Options;
using Rekindle.Core.Repositories;
using Rekindle.Core.Services;
using Rekindle.Tests.Helpers;

namespace Rekindle.Tests.Unit;

public class AuthServiceTests : IDisposable
{
    private readonly TestDatabase _db = new();
    private readonly AuthService _sut;
    private readonly UserRepository _users;

    public AuthServiceTests()
    {
        _users = new UserRepository(_db.Factory);
        var options = Options.Create(new RekindleOptions
        {
            Jwt = new JwtOptions
            {
                Secret = "test-secret-key-for-unit-tests-min-32-chars!!",
                Issuer = "Rekindle",
                Audience = "Rekindle",
                ExpiryDays = 30
            }
        });
        _sut = new AuthService(_users, options);
    }

    [Fact]
    public async Task CreateUserAsync_StoresHashedPassword_NotPlaintext()
    {
        var user = await _sut.CreateUserAsync("alice", "SuperSecret99!");

        user.PasswordHash.Should().NotBe("SuperSecret99!");
        user.PasswordHash.Should().Contain(":");
    }

    [Fact]
    public async Task CreateUserAsync_WithAdminLevel_SetsRole()
    {
        var user = await _sut.CreateUserAsync("admin", "Pass1!", permissionLevel: 4);

        user.Role.Should().Be("admin");
        user.PermissionLevel.Should().Be(4);
    }

    [Fact]
    public async Task AuthenticateAsync_CorrectCredentials_ReturnsToken()
    {
        await _sut.CreateUserAsync("bob", "CorrectPass1!");

        var token = await _sut.AuthenticateAsync("bob", "CorrectPass1!");

        token.Should().NotBeNullOrEmpty();
    }

    [Fact]
    public async Task AuthenticateAsync_WrongPassword_ReturnsNull()
    {
        await _sut.CreateUserAsync("carol", "RightPass1!");

        var token = await _sut.AuthenticateAsync("carol", "WrongPass!");

        token.Should().BeNull();
    }

    [Fact]
    public async Task AuthenticateAsync_UnknownUser_ReturnsNull()
    {
        var token = await _sut.AuthenticateAsync("nobody", "anypassword");

        token.Should().BeNull();
    }

    [Fact]
    public async Task GenerateToken_ContainsExpectedClaims()
    {
        var user = await _sut.CreateUserAsync("dave", "Pass1!", permissionLevel: 4);

        var token = _sut.GenerateToken(user);

        var handler = new JwtSecurityTokenHandler();
        var jwt = handler.ReadJwtToken(token);

        jwt.Subject.Should().Be(user.Id);
        jwt.Claims.Should().Contain(c => c.Type == JwtRegisteredClaimNames.UniqueName && c.Value == "dave");
        jwt.Claims.Should().Contain(c => c.Value == "admin");
        jwt.Claims.Should().Contain(c => c.Type == "permission_level" && c.Value == "4");
    }

    [Fact]
    public async Task TwoUsersWithSamePassword_HaveDifferentHashes()
    {
        var user1 = await _sut.CreateUserAsync("user1", "SharedPass1!");
        var user2 = await _sut.CreateUserAsync("user2", "SharedPass1!");

        user1.PasswordHash.Should().NotBe(user2.PasswordHash);
    }

    public void Dispose() => _db.Dispose();
}
