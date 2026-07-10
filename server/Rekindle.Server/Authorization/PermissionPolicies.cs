using Microsoft.AspNetCore.Authorization;

namespace Rekindle.Server.Authorization;

/// Named authorization policies for permission levels.
public static class PermissionPolicies
{
    /// Level 2+: can download archives.
    public const string CanDownload = "CanDownload";

    /// Level 3+: can add or remove media archives.
    public const string CanManageMedia = "CanManageMedia";

    /// Level 4: administrator — user management and server commands.
    public const string IsAdmin = "IsAdmin";
}

public record MinPermissionLevelRequirement(int MinLevel) : IAuthorizationRequirement;

public class MinPermissionLevelHandler : AuthorizationHandler<MinPermissionLevelRequirement>
{
    protected override Task HandleRequirementAsync(
        AuthorizationHandlerContext context,
        MinPermissionLevelRequirement requirement)
    {
        // The permission_level claim is refreshed from the database on every
        // request by the JWT OnTokenValidated event (see Program.cs), so this is
        // the user's live level — a downgrade is enforced without waiting for the
        // token to expire.
        var claim = context.User.FindFirst("permission_level");
        if (claim is not null
            && int.TryParse(claim.Value, out var level)
            && level >= requirement.MinLevel)
        {
            context.Succeed(requirement);
        }
        return Task.CompletedTask;
    }
}
