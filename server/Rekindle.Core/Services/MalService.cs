using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.Logging;

namespace Rekindle.Core.Services;

public sealed class MalService(ILogger<MalService> logger) : IDisposable
{
    private readonly HttpClient _http = new() { Timeout = TimeSpan.FromSeconds(15) };

    private const string BaseUrl = "https://api.myanimelist.net/v2/manga";
    private const string Fields  = "id,title,synopsis,genres,mean,status,start_date";

    public async Task<MalResult?> SearchAsync(string title, string clientId, CancellationToken ct = default)
    {
        var url = $"{BaseUrl}?q={Uri.EscapeDataString(title)}&limit=1&fields={Fields}";

        using var request = new HttpRequestMessage(HttpMethod.Get, url);
        request.Headers.Add("X-MAL-CLIENT-ID", clientId);

        try
        {
            using var response = await _http.SendAsync(request, ct);
            if (!response.IsSuccessStatusCode)
            {
                logger.LogWarning("MAL returned {Status} for '{Title}'", response.StatusCode, title);
                return null;
            }

            using var doc = await JsonDocument.ParseAsync(
                await response.Content.ReadAsStreamAsync(ct), cancellationToken: ct);

            if (!doc.RootElement.TryGetProperty("data", out var data) ||
                data.GetArrayLength() == 0)
                return null;

            var node = data[0].GetProperty("node");

            var genres = new List<string>();
            if (node.TryGetProperty("genres", out var genresEl) &&
                genresEl.ValueKind == JsonValueKind.Array)
            {
                foreach (var g in genresEl.EnumerateArray())
                    if (g.TryGetProperty("name", out var gName))
                        genres.Add(gName.GetString() ?? "");
            }

            int? year = null;
            if (node.TryGetProperty("start_date", out var sd) &&
                sd.ValueKind != JsonValueKind.Null)
            {
                var raw = sd.GetString();
                if (raw?.Length >= 4 && int.TryParse(raw[..4], out var y))
                    year = y;
            }

            return new MalResult
            {
                MalId    = node.GetProperty("id").GetInt32(),
                Title    = node.TryGetProperty("title", out var t) ? t.GetString() : null,
                Synopsis = node.TryGetProperty("synopsis", out var syn) ? syn.GetString() : null,
                Genres   = genres,
                Score    = node.TryGetProperty("mean", out var mean) && mean.ValueKind != JsonValueKind.Null
                              ? mean.GetDouble() : null,
                Status   = node.TryGetProperty("status", out var status) && status.ValueKind != JsonValueKind.Null
                              ? status.GetString() : null,
                Year     = year,
            };
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "MAL request failed for '{Title}'", title);
            return null;
        }
    }

    public void Dispose() => _http.Dispose();
}

public class MalResult
{
    public int     MalId    { get; init; }
    public string? Title    { get; init; }
    public string? Synopsis { get; init; }
    public List<string> Genres { get; init; } = [];
    public double? Score   { get; init; }
    public string? Status  { get; init; }
    public int?    Year    { get; init; }
}
