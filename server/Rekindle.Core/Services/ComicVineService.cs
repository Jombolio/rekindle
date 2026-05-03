using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.Logging;

namespace Rekindle.Core.Services;

/// <summary>
/// Queries the ComicVine API for comic volume metadata.
/// Rate: 200 req/resource/hour with velocity detection.
/// We enforce a 1-second minimum gap between requests to stay within the velocity limit.
/// </summary>
public sealed class ComicVineService(ILogger<ComicVineService> logger) : IDisposable
{
    private readonly HttpClient _http = new() { Timeout = TimeSpan.FromSeconds(20) };
    private DateTime _lastRequest = DateTime.MinValue;
    private readonly SemaphoreSlim _throttle = new(1, 1);

    private const string BaseUrl = "https://comicvine.gamespot.com/api";

    public async Task<ComicVineResult?> SearchVolumeAsync(
        string title,
        string apiKey,
        CancellationToken ct = default)
    {
        // Enforce a 1-second gap between requests to respect velocity detection
        await _throttle.WaitAsync(ct);
        try
        {
            var elapsed = DateTime.UtcNow - _lastRequest;
            if (elapsed < TimeSpan.FromSeconds(1))
                await Task.Delay(TimeSpan.FromSeconds(1) - elapsed, ct);
            _lastRequest = DateTime.UtcNow;

            // /search/ is ComicVine's full-text search endpoint. The /volumes/ endpoint
            // does not support a query parameter — using it returns unrelated results.
            // deck = short one-liner synopsis; description = full HTML overview.
            // Prefer deck when available, fall back to description.
            var url = $"{BaseUrl}/search/?api_key={Uri.EscapeDataString(apiKey)}" +
                      $"&format=json&query={Uri.EscapeDataString(title)}" +
                      $"&resources=volume" +
                      $"&field_list=id,name,deck,description,publisher,start_year&limit=1";

            using var request = new HttpRequestMessage(HttpMethod.Get, url);
            request.Headers.Add("User-Agent", "Rekindle/1.0");

            using var response = await _http.SendAsync(request, ct);
            if (!response.IsSuccessStatusCode)
            {
                logger.LogWarning("ComicVine returned {Status} for '{Title}'", response.StatusCode, title);
                return null;
            }

            using var doc = await JsonDocument.ParseAsync(
                await response.Content.ReadAsStreamAsync(ct), cancellationToken: ct);

            if (!doc.RootElement.TryGetProperty("results", out var results) ||
                results.ValueKind != JsonValueKind.Array ||
                results.GetArrayLength() == 0)
                return null;

            var vol = results[0];

            int? year = null;
            if (vol.TryGetProperty("start_year", out var startYear) &&
                startYear.ValueKind != JsonValueKind.Null)
            {
                var raw = startYear.GetString();
                if (raw != null && int.TryParse(raw, out var parsed))
                    year = parsed;
            }

            string? publisher = null;
            if (vol.TryGetProperty("publisher", out var pub) &&
                pub.ValueKind == JsonValueKind.Object &&
                pub.TryGetProperty("name", out var pubName))
                publisher = pubName.GetString();

            string? synopsis = null;
            if (vol.TryGetProperty("deck", out var deck) && deck.ValueKind != JsonValueKind.Null)
                synopsis = deck.GetString();
            if (string.IsNullOrWhiteSpace(synopsis) &&
                vol.TryGetProperty("description", out var desc) && desc.ValueKind != JsonValueKind.Null)
                synopsis = desc.GetString();

            return new ComicVineResult
            {
                ComicvineId = vol.GetProperty("id").GetInt32(),
                Title       = vol.TryGetProperty("name", out var name) ? name.GetString() : null,
                Synopsis    = synopsis,
                Publisher   = publisher,
                Year        = year,
            };
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "ComicVine request failed for '{Title}'", title);
            return null;
        }
        finally
        {
            _throttle.Release();
        }
    }

    public void Dispose()
    {
        _http.Dispose();
        _throttle.Dispose();
    }
}

public class ComicVineResult
{
    public int     ComicvineId { get; init; }
    public string? Title       { get; init; }
    public string? Synopsis    { get; init; }
    public string? Publisher   { get; init; }
    public int?    Year        { get; init; }
}
