using System.Net.Http.Headers;
using System.Net.Http.Json;

namespace Rekindle.Tests.Helpers;

public static class AuthHelper
{
    public static async Task<string> LoginAsync(HttpClient client, string username, string password)
    {
        var resp = await client.PostAsJsonAsync("/api/auth/login", new { username, password });
        resp.EnsureSuccessStatusCode();
        var body = await resp.Content.ReadFromJsonAsync<TokenResponse>();
        return body!.Token;
    }

    public static void SetBearerToken(this HttpClient client, string token) =>
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);

    private record TokenResponse(string Token);
}
