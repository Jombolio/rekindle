using System.Globalization;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;

namespace Rekindle.Server.Authorization;

/// <summary>
/// Decides when an in-flight JWT should be replaced, and names the channel the
/// replacement travels back on.
///
/// Tokens carry a hard absolute expiry (<c>Jwt:ExpiryDays</c>) and there is no
/// refresh-token flow, so without renewal every client is signed out the moment
/// that deadline passes — mid-session, with no recovery but a manual re-login.
/// Renewing off ordinary authenticated traffic keeps an actively-used session
/// alive indefinitely while still letting an abandoned one lapse on schedule.
/// </summary>
public static class TokenRenewal
{
    /// Response header carrying a replacement JWT. Clients persist it verbatim
    /// and send it on subsequent requests.
    public const string HeaderName = "X-Rekindle-Token";

    /// Holds the permission level the *token itself* asserted, preserved before
    /// the live database value overwrites `permission_level` (see Program.cs).
    /// Without it there is nothing left to compare against — the overwrite makes
    /// the token and the database agree by construction.
    public const string TokenPermissionLevelClaim = "token_permission_level";

    private static readonly TimeSpan MaxRenewWindow = TimeSpan.FromDays(7);

    /// <summary>
    /// How close to expiry a token must be before it is replaced. Capped at half
    /// the configured lifetime so a deliberately short <c>ExpiryDays</c> doesn't
    /// mint a new token on literally every request.
    /// </summary>
    public static TimeSpan RenewWindow(int expiryDays)
    {
        var half = TimeSpan.FromDays(Math.Max(expiryDays, 0)) / 2;
        return half < MaxRenewWindow ? half : MaxRenewWindow;
    }

    /// <summary>
    /// True when <paramref name="principal"/>'s token should be replaced: it is
    /// nearing expiry, or the permission level it asserts no longer matches
    /// <paramref name="liveLevel"/> (an admin changed it since the token issued).
    /// </summary>
    public static bool ShouldRenew(ClaimsPrincipal principal, int liveLevel, int expiryDays)
    {
        var assertedRaw = principal.FindFirst(TokenPermissionLevelClaim)?.Value;
        var asserted = assertedRaw is not null && int.TryParse(assertedRaw, out var a) ? a : -1;
        if (asserted != liveLevel)
            return true;

        var expiresAt = ExpiresAt(principal);
        return expiresAt is not null
               && expiresAt.Value - DateTimeOffset.UtcNow <= RenewWindow(expiryDays);
    }

    /// <summary>
    /// Reads the token's expiry. JwtSecurityTokenHandler's inbound claim map may
    /// rewrite `exp` to <see cref="ClaimTypes.Expiration"/>, so both spellings are
    /// checked — and the two carry different formats (Unix seconds vs ISO-8601).
    /// </summary>
    private static DateTimeOffset? ExpiresAt(ClaimsPrincipal principal)
    {
        var raw = principal.FindFirst(JwtRegisteredClaimNames.Exp)?.Value
                  ?? principal.FindFirst(ClaimTypes.Expiration)?.Value;
        if (raw is null)
            return null;

        if (long.TryParse(raw, NumberStyles.Integer, CultureInfo.InvariantCulture, out var unixSeconds))
            return DateTimeOffset.FromUnixTimeSeconds(unixSeconds);

        return DateTimeOffset.TryParse(raw, CultureInfo.InvariantCulture,
            DateTimeStyles.AdjustToUniversal, out var parsed)
            ? parsed
            : null;
    }
}
