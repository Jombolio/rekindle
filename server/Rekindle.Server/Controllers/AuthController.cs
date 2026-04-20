using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Rekindle.Core.Repositories;
using Rekindle.Core.Services;

namespace Rekindle.Server.Controllers;

[ApiController]
[Route("api/auth")]
public class AuthController(
    AuthService authService,
    UserRepository users,
    SetupTokenService setupToken) : ControllerBase
{
    [HttpPost("setup")]
    public async Task<IActionResult> Setup([FromBody] SetupRequest req)
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

    [HttpGet("setup/status")]
    public async Task<IActionResult> SetupStatus()
    {
        var needsSetup = !await users.AdminExistsAsync();
        return Ok(new { needsSetup });
    }

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

        var claimLevelStr = User.FindFirstValue("permission_level");
        var claimLevel = claimLevelStr is not null && int.TryParse(claimLevelStr, out var l) ? l : -1;

        string? freshToken = null;
        if (claimLevel != user.PermissionLevel)
            freshToken = authService.GenerateToken(user);

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
