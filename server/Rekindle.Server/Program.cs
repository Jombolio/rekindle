using System.Security.Cryptography;
using System.Text;
using System.Threading.Channels;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;
using Rekindle.Server.Authorization;
using Rekindle.Core.Database;
using Rekindle.Core.Repositories;
using Rekindle.Core.Services;

var builder = WebApplication.CreateBuilder(args);

// ------------------------------------------------------------------
// Options
// ------------------------------------------------------------------
builder.Services.Configure<RekindleOptions>(opts =>
{
    var r = builder.Configuration.GetSection("Rekindle");
    var j = builder.Configuration.GetSection("Jwt");

    opts.DataPath = r["DataPath"] ?? "/config";
    opts.CachePath = r["CachePath"] ?? "/cache";

    if (long.TryParse(r["CacheMaxSizeBytes"], out var cacheSize))
        opts.CacheMaxSizeBytes = cacheSize;

    opts.Jwt.Issuer    = j["Issuer"]   ?? "Rekindle";
    opts.Jwt.Audience  = j["Audience"] ?? "Rekindle";
    opts.Jwt.Secret    = j["Secret"]   ?? string.Empty;

    if (int.TryParse(j["ExpiryDays"], out var expiry))
        opts.Jwt.ExpiryDays = expiry;
});

// Normalize DataPath and CachePath to absolute so PhysicalFile never gets a relative path.
builder.Services.PostConfigure<RekindleOptions>(opts =>
{
    opts.DataPath  = Path.GetFullPath(opts.DataPath);
    opts.CachePath = Path.GetFullPath(opts.CachePath);
});

// ------------------------------------------------------------------
// Database — factory resolved lazily so config overrides are in effect
// ------------------------------------------------------------------
builder.Services.AddSingleton<DbConnectionFactory>(sp =>
{
    var opts = sp.GetRequiredService<IOptions<RekindleOptions>>().Value;
    Directory.CreateDirectory(opts.DataPath);

    // Persist JWT secret to disk if not explicitly configured
    opts.Jwt.Secret = ResolveJwtSecret(opts.DataPath, opts.Jwt.Secret);

    var dbPath = Path.Combine(opts.DataPath, "rekindle.db");
    return new DbConnectionFactory($"Data Source={dbPath};");
});

builder.Services.AddScoped<DbInitializer>();

// ------------------------------------------------------------------
// Repositories & Services
// ------------------------------------------------------------------
builder.Services.AddScoped<UserRepository>();
builder.Services.AddScoped<LibraryRepository>();
builder.Services.AddScoped<MediaRepository>();
builder.Services.AddScoped<ProgressRepository>();
builder.Services.AddScoped<AuthService>();
builder.Services.AddSingleton<SetupTokenService>();
builder.Services.AddSingleton<ScanProgressTracker>();
builder.Services.AddScoped<LibraryScannerService>();
builder.Services.AddSingleton<ArchiveService>();

var coverChannel = Channel.CreateUnbounded<CoverJob>(new UnboundedChannelOptions { SingleReader = true });
builder.Services.AddSingleton(coverChannel);
builder.Services.AddHostedService<CoverGenerationService>();

// ------------------------------------------------------------------
// Authentication
// JWT parameters are configured post-startup via IPostConfigureOptions
// so the resolved secret (from disk if needed) is always used.
// ------------------------------------------------------------------
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer();

builder.Services.AddSingleton<IPostConfigureOptions<JwtBearerOptions>, JwtBearerPostConfigure>();
builder.Services.AddSingleton<IAuthorizationHandler, MinPermissionLevelHandler>();
builder.Services.AddAuthorization(opts =>
{
    opts.AddPolicy(PermissionPolicies.CanDownload,
        p => p.AddRequirements(new MinPermissionLevelRequirement(2)));
    opts.AddPolicy(PermissionPolicies.CanManageMedia,
        p => p.AddRequirements(new MinPermissionLevelRequirement(3)));
    opts.AddPolicy(PermissionPolicies.IsAdmin,
        p => p.AddRequirements(new MinPermissionLevelRequirement(4)));
});
builder.Services.AddControllers();

// ------------------------------------------------------------------
// App
// ------------------------------------------------------------------
var app = builder.Build();

// Trigger DB factory creation (resolves secret, creates dirs) then init schema
using (var scope = app.Services.CreateScope())
{
    _ = scope.ServiceProvider.GetRequiredService<DbConnectionFactory>();
    var dbInit = scope.ServiceProvider.GetRequiredService<DbInitializer>();
    await dbInit.InitializeAsync();

    // If no admin exists yet, generate a setup token and print it to the log.
    // The token must be supplied to POST /api/auth/setup — a remote attacker
    // who can reach the port cannot read server stdout and therefore cannot
    // claim the admin account before the legitimate owner.
    var userRepo = scope.ServiceProvider.GetRequiredService<UserRepository>();
    if (!await userRepo.AdminExistsAsync())
    {
        var setupTokenService = app.Services.GetRequiredService<SetupTokenService>();
        var token = setupTokenService.Generate();
        var logger = app.Services.GetRequiredService<ILogger<Program>>();
        logger.LogWarning("════════════════════════════════════════════════════════");
        logger.LogWarning("  REKINDLE FIRST-TIME SETUP");
        logger.LogWarning("  No admin account exists. Use the token below to");
        logger.LogWarning("  complete setup via POST /api/auth/setup.");
        logger.LogWarning("  Setup token: {Token}", token);
        logger.LogWarning("  This token is one-time and invalidated after use.");
        logger.LogWarning("════════════════════════════════════════════════════════");
    }
}

app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();

await app.RunAsync();

// ------------------------------------------------------------------
// JWT secret resolution
// ------------------------------------------------------------------
static string ResolveJwtSecret(string dataPath, string configured)
{
    if (!string.IsNullOrWhiteSpace(configured))
        return configured;

    var keyFile = Path.Combine(dataPath, "jwt_secret.key");
    if (File.Exists(keyFile))
        return File.ReadAllText(keyFile).Trim();

    var secret = Convert.ToBase64String(RandomNumberGenerator.GetBytes(48));
    File.WriteAllText(keyFile, secret);
    return secret;
}

// ------------------------------------------------------------------
// Post-configure JWT bearer to pick up the resolved secret from options
// ------------------------------------------------------------------
internal sealed class JwtBearerPostConfigure(IOptions<RekindleOptions> rekindleOptions)
    : IPostConfigureOptions<JwtBearerOptions>
{
    public void PostConfigure(string? name, JwtBearerOptions options)
    {
        var jwt = rekindleOptions.Value.Jwt;
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwt.Secret));

        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer           = true,
            ValidateAudience         = true,
            ValidateLifetime         = true,
            ValidateIssuerSigningKey = true,
            ValidIssuer              = jwt.Issuer,
            ValidAudience            = jwt.Audience,
            IssuerSigningKey         = key
        };
    }
}

// Required for WebApplicationFactory<Program> in integration tests
public partial class Program { }
