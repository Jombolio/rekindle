using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.Logging;

namespace Rekindle.Core.Services;

public sealed class AniListService : IDisposable
{
    private readonly HttpClient _http;
    private readonly SlidingWindowCounter _limiter;
    private readonly ILogger<AniListService> _logger;

    private const string Endpoint = "https://graphql.anilist.co";

    private static readonly string Query = """
        query ($search: String) {
          Media(search: $search, type: MANGA, isAdult: false) {
            id
            title { romaji english }
            description(asHtml: false)
            genres
            averageScore
            status
            startDate { year }
          }
        }
        """;

    public AniListService(ILogger<AniListService> logger)
    {
        _logger = logger;
        _http = new HttpClient { Timeout = TimeSpan.FromSeconds(15) };
        _http.DefaultRequestHeaders.Add("Accept", "application/json");
        _limiter = new SlidingWindowCounter(maxRequests: 30, window: TimeSpan.FromMinutes(1));
    }

    public async Task<AniListResult?> SearchAsync(string title, CancellationToken ct = default)
    {
        if (!_limiter.TryAcquire())
        {
            _logger.LogWarning("AniList rate limit reached — request dropped for '{Title}'", title);
            return null;
        }

        var payload = new
        {
            query = Query,
            variables = new { search = title },
        };

        try
        {
            using var response = await _http.PostAsJsonAsync(Endpoint, payload, ct);
            if (!response.IsSuccessStatusCode)
            {
                _logger.LogWarning("AniList returned {Status} for '{Title}'", response.StatusCode, title);
                return null;
            }

            using var doc = await JsonDocument.ParseAsync(
                await response.Content.ReadAsStreamAsync(ct), cancellationToken: ct);

            if (!doc.RootElement.TryGetProperty("data", out var data) ||
                !data.TryGetProperty("Media", out var media) ||
                media.ValueKind == JsonValueKind.Null)
                return null;

            var titleEl   = media.GetProperty("title");
            var startDate = media.TryGetProperty("startDate", out var sd) ? sd : default;

            return new AniListResult
            {
                AnilistId = media.GetProperty("id").GetInt32(),
                Title     = titleEl.TryGetProperty("english", out var eng) && eng.ValueKind != JsonValueKind.Null
                               ? eng.GetString()
                               : titleEl.TryGetProperty("romaji", out var rom) ? rom.GetString() : null,
                Synopsis  = media.TryGetProperty("description", out var desc) && desc.ValueKind != JsonValueKind.Null
                               ? desc.GetString() : null,
                Genres    = media.TryGetProperty("genres", out var genres) && genres.ValueKind == JsonValueKind.Array
                               ? genres.EnumerateArray().Select(g => g.GetString() ?? "").Where(g => g.Length > 0).ToList()
                               : [],
                Score     = media.TryGetProperty("averageScore", out var score) && score.ValueKind != JsonValueKind.Null
                               ? (double?)score.GetDouble() / 10.0 : null,
                Status    = media.TryGetProperty("status", out var status) && status.ValueKind != JsonValueKind.Null
                               ? status.GetString() : null,
                Year      = startDate.ValueKind != JsonValueKind.Undefined &&
                            startDate.TryGetProperty("year", out var yr) &&
                            yr.ValueKind != JsonValueKind.Null
                               ? yr.GetInt32() : null,
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "AniList request failed for '{Title}'", title);
            return null;
        }
    }

    public void Dispose() => _http.Dispose();
}

/// <summary>
/// Thread-safe sliding-window counter. Records timestamps of recent calls
/// and rejects new ones once <see cref="MaxRequests"/> have been made within
/// the rolling <see cref="Window"/>.
/// </summary>
internal sealed class SlidingWindowCounter(int maxRequests, TimeSpan window)
{
    private readonly Queue<DateTime> _timestamps = new();
    private readonly object _lock = new();

    public bool TryAcquire()
    {
        var now = DateTime.UtcNow;
        lock (_lock)
        {
            // Evict timestamps older than the window
            while (_timestamps.Count > 0 && (now - _timestamps.Peek()) >= window)
                _timestamps.Dequeue();

            if (_timestamps.Count >= maxRequests)
                return false;

            _timestamps.Enqueue(now);
            return true;
        }
    }
}

public class AniListResult
{
    public int    AnilistId { get; init; }
    public string? Title    { get; init; }
    public string? Synopsis { get; init; }
    public List<string> Genres { get; init; } = [];
    public double? Score   { get; init; }
    public string? Status  { get; init; }
    public int?    Year    { get; init; }
}
