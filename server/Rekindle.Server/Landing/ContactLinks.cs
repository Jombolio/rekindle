namespace Rekindle.Server.Landing;

/// The administrator's contact links, bound from <c>Rekindle:Contacts</c> in
/// appsettings.json. Reloaded when the file changes, no restart needed.
public class LandingOptions
{
    public List<ContactLinkOptions> Contacts { get; set; } = [];

    /// <c>Rekindle:LandingTheme</c>: "System" (the default) follows the
    /// visitor's light or dark setting; "Light" or "Dark" fixes it.
    public string? LandingTheme { get; set; }
}

public enum LandingTheme { System, Light, Dark }

/// One entry as the administrator wrote it, before any checks.
public class ContactLinkOptions
{
    /// What the link is called on the page, e.g. "Discord". Optional.
    public string? Name { get; set; }

    /// An http, https or mailto URL. A bare email address is taken as mailto.
    public string? Url { get; set; }
}

/// A contact link that passed the checks and is safe to put in an href.
/// Nothing here is HTML-encoded yet; the page does that when it writes it out.
public sealed record ContactLink(string Name, string Href, string Detail, bool IsEmail);

public static class ContactLinks
{
    private const int MaxNameLength = 60;
    private const int MaxDetailLength = 60;
    private const int MaxUrlLength = 2048;

    /// The entries that can be shown, in the order given. [rejected] gets the
    /// raw URL of each one that couldn't, so the server can say why.
    public static IReadOnlyList<ContactLink> FromOptions(
        IEnumerable<ContactLinkOptions>? entries, ICollection<string>? rejected = null)
    {
        var links = new List<ContactLink>();
        foreach (var entry in entries ?? [])
        {
            if (entry is null) continue;
            if (TryCreate(entry.Name, entry.Url, out var link))
                links.Add(link);
            else
                rejected?.Add(entry.Url ?? "(no Url)");
        }
        return links;
    }

    /// Accepts only http and https URLs with a host, and mailto addresses.
    /// Everything else (javascript:, data:, relative paths, garbage) is refused.
    public static bool TryCreate(string? name, string? url, out ContactLink link)
    {
        link = null!;
        var raw = url?.Trim();
        if (string.IsNullOrEmpty(raw) || raw.Length > MaxUrlLength) return false;
        if (raw.Any(c => char.IsControl(c) || char.IsWhiteSpace(c))) return false;

        // "me@example.com" on its own means email.
        if (!raw.Contains(':') && raw.Contains('@') && !raw.Contains('/'))
            raw = "mailto:" + raw;

        if (!Uri.TryCreate(raw, UriKind.Absolute, out var uri)) return false;

        string detail;
        bool isEmail;
        switch (uri.Scheme)
        {
            case "http":
            case "https":
                if (string.IsNullOrEmpty(uri.Host)) return false;
                if (!string.IsNullOrEmpty(uri.UserInfo)) return false;
                var rest = uri.PathAndQuery + uri.Fragment;
                detail = HostWithoutWww(uri) + (rest == "/" ? "" : rest.TrimEnd('/'));
                isEmail = false;
                break;

            case "mailto":
                var address = Uri.UnescapeDataString(raw["mailto:".Length..].Split('?')[0]);
                var at = address.IndexOf('@');
                if (at <= 0 || at == address.Length - 1) return false;
                detail = address;
                isEmail = true;
                break;

            default:
                return false;
        }

        var label = name?.Trim();
        if (string.IsNullOrEmpty(label) || label.Any(char.IsControl))
            label = isEmail ? "Email" : HostWithoutWww(uri);

        link = new ContactLink(
            Shorten(label, MaxNameLength),
            uri.AbsoluteUri,
            Shorten(detail, MaxDetailLength),
            isEmail);
        return true;
    }

    private static string HostWithoutWww(Uri uri) =>
        uri.Host.StartsWith("www.", StringComparison.OrdinalIgnoreCase) ? uri.Host[4..] : uri.Host;

    private static string Shorten(string value, int max) =>
        value.Length <= max ? value : value[..(max - 1)] + "…";
}
