using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Rekindle.Core.Repositories;
using Rekindle.Core.Services;
using Rekindle.Server.Authorization;

namespace Rekindle.Server.Controllers;

[ApiController]
[Route("api/auth")]
public class AuthController(
    AuthService authService,
    UserRepository users,
    SetupTokenService setupToken) : ControllerBase
{
    // Serializes setup so the AdminExists check, token validation, admin creation
    // and token consumption are atomic — otherwise two concurrent requests could
    // each create a level-4 admin from the one-time token (TOCTOU).
    private static readonly SemaphoreSlim SetupLock = new(1, 1);

    [EnableRateLimiting("auth")]
    [HttpPost("setup")]
    public async Task<IActionResult> Setup([FromBody] SetupRequest req)
    {
        await SetupLock.WaitAsync();
        try
        {
            if (await users.AdminExistsAsync())
                return Conflict(new { error = "Admin account already exists." });

            if (string.IsNullOrWhiteSpace(req.Username) || string.IsNullOrWhiteSpace(req.Password))
                return BadRequest(new { error = "Username and password are required." });

            if (!setupToken.Validate(req.SetupToken))
                return Unauthorized(new { error = "Invalid or missing setup token. Check the server log." });

            var user = await authService.CreateUserAsync(req.Username, req.Password, permissionLevel: 4);
            var token = authService.GenerateToken(user);

            setupToken.Consume();

            return Ok(new { token, username = user.Username, permissionLevel = user.PermissionLevel });
        }
        finally
        {
            SetupLock.Release();
        }
    }

    [HttpGet("setup/status")]
    public async Task<IActionResult> SetupStatus()
    {
        var needsSetup = !await users.AdminExistsAsync();
        return Ok(new { needsSetup });
    }

    [EnableRateLimiting("auth")]
    [HttpPost("login")]
    public async Task<IActionResult> Login([FromBody] LoginRequest req)
    {
        var token = await authService.AuthenticateAsync(req.Username, req.Password);
        if (token is null)
            return Unauthorized(new { error = "Invalid credentials." });

        var user = await users.GetByUsernameAsync(req.Username);
        return Ok(new { token, username = user!.Username, permissionLevel = user.PermissionLevel });
    }

    [Authorize]
    [HttpGet("me")]
    public async Task<IActionResult> Me()
    {
        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier)
                     ?? User.FindFirstValue(System.IdentityModel.Tokens.Jwt.JwtRegisteredClaimNames.Sub);

        if (userId is null) return Unauthorized();

        var user = await users.GetByIdAsync(userId);
        if (user is null) return NotFound();

        // Renewal is decided in one place — the JWT OnTokenValidated event — which
        // has already put any replacement on the response header. Echo it in the
        // body so a client that only reads JSON still picks it up. (Comparing
        // permission_level here would never fire: that claim is overwritten with
        // the live DB value on every request, so it always matches.)
        var freshToken = Response.Headers[TokenRenewal.HeaderName].FirstOrDefault();

        return Ok(new
        {
            id = user.Id,
            username = user.Username,
            permissionLevel = user.PermissionLevel,
            createdAt = user.CreatedAt,
            token = freshToken
        });
    }

    public record LoginRequest(string Username, string Password);
    public record SetupRequest(string Username, string Password, string? SetupToken);
}
