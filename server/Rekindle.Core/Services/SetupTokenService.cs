using System.Security.Cryptography;

namespace Rekindle.Core.Services;

/// <summary>
/// Holds the one-time setup token that is printed to the server log on first boot.
/// The token is required to call POST /api/auth/setup, preventing a remote attacker
/// who can reach the port from claiming the admin account before the legitimate owner.
/// It is cleared immediately after a successful setup.
/// </summary>
public sealed class SetupTokenService
{
    private string? _token;

    /// <summary>
    /// Generate and store a new token. Idempotent — calling it twice returns the same token.
    /// </summary>
    public string Generate()
    {
        _token ??= Convert.ToHexString(RandomNumberGenerator.GetBytes(16));
        return _token;
    }

    /// <summary>True if setup has not yet been completed and a token is active.</summary>
    public bool IsActive => _token is not null;

    /// <summary>
    /// Validates the supplied token using a constant-time comparison.
    /// Returns false if no token is active (setup already done) or the value is wrong.
    /// </summary>
    public bool Validate(string? candidate)
    {
        if (_token is null || candidate is null)
            return false;

        var a = System.Text.Encoding.UTF8.GetBytes(_token);
        var b = System.Text.Encoding.UTF8.GetBytes(candidate);
        return CryptographicOperations.FixedTimeEquals(a, b);
    }

    /// <summary>Invalidate the token after successful setup.</summary>
    public void Consume() => _token = null;
}
