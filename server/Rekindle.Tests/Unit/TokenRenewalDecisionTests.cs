using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using FluentAssertions;
using Rekindle.Server.Authorization;
using Xunit;

namespace Rekindle.Tests.Unit;

public class TokenRenewalDecisionTests
{
    private static ClaimsPrincipal Principal(
        int assertedLevel, DateTimeOffset expiresAt, bool isoExpiry = false)
    {
        Claim expiry = isoExpiry
            ? new Claim(ClaimTypes.Expiration, expiresAt.UtcDateTime.ToString("O"))
            : new Claim(JwtRegisteredClaimNames.Exp, expiresAt.ToUnixTimeSeconds().ToString());

        return new ClaimsPrincipal(new ClaimsIdentity(
            [new Claim(TokenRenewal.TokenPermissionLevelClaim, assertedLevel.ToString()), expiry],
            "Test"));
    }

    [Fact]
    public void RenewWindow_CapsAtSevenDays() =>
        TokenRenewal.RenewWindow(30).Should().Be(TimeSpan.FromDays(7));

    [Fact]
    public void RenewWindow_ForShortLifetimes_IsHalfTheLifetime() =>
        TokenRenewal.RenewWindow(2).Should().Be(TimeSpan.FromDays(1));

    [Fact]
    public void ShouldRenew_WhenTokenIsFresh_IsFalse() =>
        TokenRenewal.ShouldRenew(Principal(4, DateTimeOffset.UtcNow.AddDays(29)), 4, 30)
            .Should().BeFalse();

    [Fact]
    public void ShouldRenew_WhenInsideTheWindow_IsTrue() =>
        TokenRenewal.ShouldRenew(Principal(4, DateTimeOffset.UtcNow.AddDays(3)), 4, 30)
            .Should().BeTrue();

    [Fact]
    public void ShouldRenew_WhenPermissionLevelDrifted_IsTrue() =>
        TokenRenewal.ShouldRenew(Principal(2, DateTimeOffset.UtcNow.AddDays(29)), 4, 30)
            .Should().BeTrue();

    // The inbound claim map may present `exp` as ClaimTypes.Expiration holding an
    // ISO-8601 string instead of Unix seconds. If the expiry check understood only
    // one spelling it would silently never renew, which is the exact failure this
    // whole mechanism exists to prevent.
    [Fact]
    public void ShouldRenew_ReadsIso8601ExpirationClaim() =>
        TokenRenewal.ShouldRenew(Principal(4, DateTimeOffset.UtcNow.AddDays(3), isoExpiry: true), 4, 30)
            .Should().BeTrue();

    [Fact]
    public void ShouldRenew_WithNoExpiryClaim_IsFalse()
    {
        var principal = new ClaimsPrincipal(new ClaimsIdentity(
            [new Claim(TokenRenewal.TokenPermissionLevelClaim, "4")], "Test"));

        TokenRenewal.ShouldRenew(principal, 4, 30).Should().BeFalse();
    }

    // A token that asserted no level at all has nothing to compare against, so it
    // is treated as drifted and replaced rather than quietly trusted.
    [Fact]
    public void ShouldRenew_WithNoAssertedLevel_IsTrue()
    {
        var principal = new ClaimsPrincipal(new ClaimsIdentity(
            [new Claim(JwtRegisteredClaimNames.Exp,
                DateTimeOffset.UtcNow.AddDays(29).ToUnixTimeSeconds().ToString())],
            "Test"));

        TokenRenewal.ShouldRenew(principal, 4, 30).Should().BeTrue();
    }
}
