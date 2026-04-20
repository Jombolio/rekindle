using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Rekindle.Server.Authorization;
using Rekindle.Core.Repositories;
using Rekindle.Core.Services;

namespace Rekindle.Server.Controllers;

[ApiController]
[Route("api/users")]
[Authorize(Policy = PermissionPolicies.IsAdmin)]
public class UsersController(
    UserRepository users,
    AuthService authService) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> GetAll()
    {
        var all = await users.GetAllAsync();
        return Ok(all.Select(u => new
        {
            id = u.Id,
            username = u.Username,
            permissionLevel = u.PermissionLevel,
            createdAt = u.CreatedAt,
        }));
    }

    [HttpPost]
    public async Task<IActionResult> Create([FromBody] CreateUserRequest req)
    {
        if (string.IsNullOrWhiteSpace(req.Username) || string.IsNullOrWhiteSpace(req.Password))
            return BadRequest(new { error = "Username and password are required." });

        if (req.Password.Length < 8)
            return BadRequest(new { error = "Password must be at least 8 characters." });

        // Admin accounts can only be created via the initial setup flow.
        if (req.PermissionLevel is < 1 or > 3)
            return BadRequest(new { error = "Permission level must be between 1 and 3." });

        var existing = await users.GetByUsernameAsync(req.Username);
        if (existing is not null)
            return Conflict(new { error = "Username already taken." });

        var user = await authService.CreateUserAsync(req.Username, req.Password, req.PermissionLevel);
        return CreatedAtAction(nameof(GetById), new { id = user.Id }, new
        {
            id = user.Id,
            username = user.Username,
            permissionLevel = user.PermissionLevel,
            createdAt = user.CreatedAt,
        });
    }

    [HttpGet("{id}")]
    public async Task<IActionResult> GetById(string id)
    {
        var user = await users.GetByIdAsync(id);
        if (user is null) return NotFound();
        return Ok(new
        {
            id = user.Id,
            username = user.Username,
            permissionLevel = user.PermissionLevel,
            createdAt = user.CreatedAt,
        });
    }

    [HttpPut("{id}/permission")]
    public async Task<IActionResult> UpdatePermission(string id, [FromBody] UpdatePermissionRequest req)
    {
        // Admin-level (4) is reserved — it can only be set via the initial setup.
        if (req.PermissionLevel is < 1 or > 3)
            return BadRequest(new { error = "Permission level must be between 1 and 3." });

        var callerId = GetCallerId();

        var user = await users.GetByIdAsync(id);
        if (user is null) return NotFound();

        // Admins cannot have their permission level changed through this endpoint.
        if (user.PermissionLevel >= 4)
            return BadRequest(new { error = "Admin accounts cannot be modified." });

        // Prevent self-modification.
        if (callerId == id)
            return BadRequest(new { error = "You cannot change your own permission level." });

        await users.UpdatePermissionLevelAsync(id, req.PermissionLevel);
        return Ok(new { id, permissionLevel = req.PermissionLevel });
    }

    [HttpPut("{id}/password")]
    public async Task<IActionResult> UpdatePassword(string id, [FromBody] UpdatePasswordRequest req)
    {
        if (string.IsNullOrWhiteSpace(req.Password) || req.Password.Length < 8)
            return BadRequest(new { error = "Password must be at least 8 characters." });

        var user = await users.GetByIdAsync(id);
        if (user is null) return NotFound();

        // Only the admin who owns the account can change an admin's password.
        if (user.PermissionLevel >= 4 && GetCallerId() != id)
            return Forbid();

        await authService.SetPasswordAsync(id, req.Password);
        return NoContent();
    }

    [HttpDelete("{id}")]
    public async Task<IActionResult> Delete(string id)
    {
        if (GetCallerId() == id)
            return BadRequest(new { error = "You cannot delete your own account." });

        var user = await users.GetByIdAsync(id);
        if (user is null) return NotFound();

        if (user.PermissionLevel >= 4)
            return BadRequest(new { error = "Admin accounts cannot be deleted." });

        await users.DeleteAsync(id);
        return NoContent();
    }

    private string? GetCallerId() =>
        User.FindFirstValue(ClaimTypes.NameIdentifier)
        ?? User.FindFirstValue(System.IdentityModel.Tokens.Jwt.JwtRegisteredClaimNames.Sub);

    public record CreateUserRequest(string Username, string Password, int PermissionLevel = 2);
    public record UpdatePermissionRequest(int PermissionLevel);
    public record UpdatePasswordRequest(string Password);
}
