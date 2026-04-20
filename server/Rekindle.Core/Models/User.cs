namespace Rekindle.Core.Models;

public class User
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string Username { get; set; } = string.Empty;
    public string PasswordHash { get; set; } = string.Empty;

    /// <summary>
    /// 1 = read-only, 2 = can download, 3 = can manage media, 4 = admin
    /// </summary>
    public int PermissionLevel { get; set; } = 2;

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    /// Derived string role used for JWT ClaimTypes.Role and legacy checks.
    public string Role => PermissionLevel >= 4 ? "admin" : "user";
}
