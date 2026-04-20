namespace Rekindle.Core.Services;

public class RekindleOptions
{
    public string DataPath { get; set; } = "/config";
    public string CachePath { get; set; } = "/cache";
    public long CacheMaxSizeBytes { get; set; } = 10L * 1024 * 1024 * 1024;
    public JwtOptions Jwt { get; set; } = new();
}

public class JwtOptions
{
    public string Secret { get; set; } = string.Empty;
    public string Issuer { get; set; } = "Rekindle";
    public string Audience { get; set; } = "Rekindle";
    public int ExpiryDays { get; set; } = 30;
}
