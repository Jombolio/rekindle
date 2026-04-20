using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Konscious.Security.Cryptography;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;
using Rekindle.Core.Models;
using Rekindle.Core.Repositories;

namespace Rekindle.Core.Services;

public class AuthService(UserRepository users, IOptions<RekindleOptions> options)
{
    private const int SaltSize = 16;
    private const int HashSize = 32;
    private const int Iterations = 4;
    private const int MemorySize = 65536;
    private const int Parallelism = 8;

    public async Task<User> CreateUserAsync(string username, string password, int permissionLevel = 2)
    {
        var salt = RandomNumberGenerator.GetBytes(SaltSize);
        var hash = await ComputeHashAsync(Encoding.UTF8.GetBytes(password), salt);

        var user = new User
        {
            Id = Guid.NewGuid().ToString(),
            Username = username,
            PasswordHash = $"{Convert.ToBase64String(salt)}:{Convert.ToBase64String(hash)}",
            PermissionLevel = permissionLevel,
            CreatedAt = DateTime.UtcNow
        };

        await users.InsertAsync(user);
        return user;
    }

    public async Task<string?> AuthenticateAsync(string username, string password)
    {
        var user = await users.GetByUsernameAsync(username);
        if (user is null)
            return null;

        var parts = user.PasswordHash.Split(':');
        if (parts.Length != 2)
            return null;

        var salt = Convert.FromBase64String(parts[0]);
        var storedHash = Convert.FromBase64String(parts[1]);
        var inputHash = await ComputeHashAsync(Encoding.UTF8.GetBytes(password), salt);

        if (!CryptographicOperations.FixedTimeEquals(inputHash, storedHash))
            return null;

        return GenerateToken(user);
    }

    public string GenerateToken(User user)
    {
        var opts = options.Value.Jwt;
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(opts.Secret));
        var creds = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);

        var claims = new[]
        {
            new Claim(JwtRegisteredClaimNames.Sub, user.Id),
            new Claim(JwtRegisteredClaimNames.UniqueName, user.Username),
            new Claim(ClaimTypes.Role, user.Role),
            new Claim("permission_level", user.PermissionLevel.ToString()),
            new Claim(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString())
        };

        var token = new JwtSecurityToken(
            issuer: opts.Issuer,
            audience: opts.Audience,
            claims: claims,
            expires: DateTime.UtcNow.AddDays(opts.ExpiryDays),
            signingCredentials: creds);

        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    public async Task SetPasswordAsync(string userId, string newPassword)
    {
        var salt = RandomNumberGenerator.GetBytes(SaltSize);
        var hash = await ComputeHashAsync(Encoding.UTF8.GetBytes(newPassword), salt);
        var passwordHash = $"{Convert.ToBase64String(salt)}:{Convert.ToBase64String(hash)}";
        await users.UpdatePasswordHashAsync(userId, passwordHash);
    }

    private static async Task<byte[]> ComputeHashAsync(byte[] password, byte[] salt)
    {
        var argon2 = new Argon2id(password)
        {
            Salt = salt,
            DegreeOfParallelism = Parallelism,
            MemorySize = MemorySize,
            Iterations = Iterations
        };
        return await argon2.GetBytesAsync(HashSize);
    }
}
