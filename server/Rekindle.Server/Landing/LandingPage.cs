using System.Net;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Options;

namespace Rekindle.Server.Landing;

/// The page someone sees when they open the server's address in a web browser.
/// Rekindle is read in its apps, so the page says what Rekindle is, where to get
/// the apps and which address to give them. Everything is in the one response
/// plus the icon, so it works offline on a LAN with nothing fetched from outside.
public sealed class LandingPage
{
    public const string IconPath = "rekindle-icon.png";

    public const string GiteaReleases = "https://git.jombo.uk/Jombo/rekindle/releases";
    public const string GitHubReleases = "https://github.com/Jombolio/rekindle/releases";
    public const string FDroidRepo = "https://fdroid.jombo.uk/repo";
    public const string GiteaRepo = "https://git.jombo.uk/Jombo/rekindle";
    public const string GitHubRepo = "https://github.com/Jombolio/rekindle";
    public const string Wiki = "https://github.com/Jombolio/rekindle/wiki";

    private static readonly Lazy<byte[]> Icon = new(() =>
    {
        using var stream = typeof(LandingPage).Assembly
            .GetManifestResourceStream("Rekindle.Server.Landing.rekindle-icon.png")
            ?? throw new InvalidOperationException("The landing page icon is missing from the build.");
        using var copy = new MemoryStream();
        stream.CopyTo(copy);
        return copy.ToArray();
    });

    private readonly IOptionsMonitor<LandingOptions> options;
    private readonly ILogger<LandingPage> logger;
    private readonly Lock gate = new();
    private LandingOptions? cachedFrom;
    private IReadOnlyList<ContactLink> cached = [];
    private LandingTheme cachedTheme;

    public LandingPage(IOptionsMonitor<LandingOptions> options, ILogger<LandingPage> logger)
    {
        this.options = options;
        this.logger = logger;
    }

    /// The contact links that can be shown right now. Worked out again only when
    /// appsettings.json changes, which is also when a bad entry gets logged.
    public IReadOnlyList<ContactLink> Contacts => Current().Contacts;

    /// The colour scheme the administrator chose for the page.
    public LandingTheme Theme => Current().Theme;

    private (IReadOnlyList<ContactLink> Contacts, LandingTheme Theme) Current()
    {
        var current = options.CurrentValue;
        lock (gate)
        {
            if (!ReferenceEquals(current, cachedFrom))
            {
                var rejected = new List<string>();
                cached = ContactLinks.FromOptions(current.Contacts, rejected);
                foreach (var url in rejected)
                    logger.LogWarning(
                        "Rekindle:Contacts entry {Url} isn't shown on the landing page: only http, https and mailto links are allowed",
                        url);

                if (!TryParseTheme(current.LandingTheme, out cachedTheme))
                    logger.LogWarning(
                        "Rekindle:LandingTheme {Theme} isn't one of System, Light or Dark; following the visitor's setting",
                        current.LandingTheme);
                cachedFrom = current;
            }
            return (cached, cachedTheme);
        }
    }

    /// Empty means System. Case doesn't matter; numbers aren't accepted.
    public static bool TryParseTheme(string? value, out LandingTheme theme)
    {
        theme = LandingTheme.System;
        var trimmed = value?.Trim();
        if (string.IsNullOrEmpty(trimmed)) return true;
        if (trimmed.All(char.IsLetter) && Enum.TryParse(trimmed, ignoreCase: true, out theme)) return true;
        theme = LandingTheme.System;
        return false;
    }

    public static void Map(WebApplication app)
    {
        app.MapMethods("/", [HttpMethods.Get, HttpMethods.Head], (HttpContext context, LandingPage page) =>
        {
            var nonce = Convert.ToBase64String(RandomNumberGenerator.GetBytes(16));
            var headers = context.Response.Headers;
            headers.ContentSecurityPolicy =
                $"default-src 'none'; img-src 'self'; style-src 'nonce-{nonce}'; script-src 'nonce-{nonce}'; " +
                "base-uri 'none'; form-action 'none'; frame-ancestors 'none'";
            headers.XContentTypeOptions = "nosniff";
            headers["Referrer-Policy"] = "no-referrer";
            headers.CacheControl = "no-cache";

            var html = Render(AddressOf(context.Request), page.Contacts, nonce, page.Theme);
            return Results.Content(html, "text/html; charset=utf-8", Encoding.UTF8);
        }).AllowAnonymous().ExcludeFromDescription();

        app.MapMethods("/" + IconPath, [HttpMethods.Get, HttpMethods.Head], (HttpContext context) =>
        {
            context.Response.Headers.CacheControl = "public, max-age=86400";
            return Results.Bytes(Icon.Value, "image/png");
        }).AllowAnonymous().ExcludeFromDescription();
    }

    /// The address as this request reached the server. Behind a reverse proxy
    /// that terminates TLS this says http, so the page corrects it from the
    /// browser's own location once it loads.
    public static string AddressOf(HttpRequest request)
    {
        var host = request.Host.HasValue ? request.Host.Value : "localhost:8080";
        return $"{request.Scheme}://{host}{request.PathBase}".TrimEnd('/');
    }

    private static string E(string value) => WebUtility.HtmlEncode(value);

    private static string Version()
    {
        var version = typeof(LandingPage).Assembly
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion ?? "";
        var plus = version.IndexOf('+');
        return plus >= 0 ? version[..plus] : version;
    }

    public static string Render(string address, IReadOnlyList<ContactLink> contacts, string nonce,
        LandingTheme theme = LandingTheme.System)
    {
        var themeAttribute = theme switch
        {
            LandingTheme.Light => " data-theme=\"light\"",
            LandingTheme.Dark => " data-theme=\"dark\"",
            _ => "",
        };
        var colorScheme = theme switch
        {
            LandingTheme.Light => "light",
            LandingTheme.Dark => "dark",
            _ => "light dark",
        };
        var contactSection = contacts.Count == 0 ? "" : RenderContacts(contacts);
        var version = Version();
        var versionText = version.Length == 0 ? "" : $" {E(version)}";

        return $$"""
<!doctype html>
<html lang="en"{{themeAttribute}}>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="{{colorScheme}}">
<meta name="robots" content="noindex">
<title>Rekindle</title>
<link rel="icon" type="image/png" href="{{IconPath}}">
<style nonce="{{E(nonce)}}">
:root {
  --primary: #6750a4;
  --on-primary: #ffffff;
  --primary-container: #eaddff;
  --on-primary-container: #21005d;
  --bg: #f5f2ed;
  --card: #ffffff;
  --card-alt: #efebe5;
  --chip: #e9e5df;
  --text: #1d1b20;
  --muted: #49454f;
  --line: #cac4d0;
  color-scheme: light;
}
/* Dark: the visitor's setting, unless the administrator fixed the theme. */
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    --primary: #d0bcff;
    --on-primary: #381e72;
    --primary-container: #4f378b;
    --on-primary-container: #eaddff;
    --bg: #141218;
    --card: #1d1b20;
    --card-alt: #211f26;
    --chip: #2b2930;
    --text: #e6e0e9;
    --muted: #cac4d0;
    --line: #49454f;
    color-scheme: dark;
  }
}
:root[data-theme="dark"] {
  --primary: #d0bcff;
  --on-primary: #381e72;
  --primary-container: #4f378b;
  --on-primary-container: #eaddff;
  --bg: #141218;
  --card: #1d1b20;
  --card-alt: #211f26;
  --chip: #2b2930;
  --text: #e6e0e9;
  --muted: #cac4d0;
  --line: #49454f;
  color-scheme: dark;
}
* { box-sizing: border-box; }
html { -webkit-text-size-adjust: 100%; }
body {
  margin: 0;
  background: var(--bg);
  color: var(--text);
  font: 16px/1.5 system-ui, -apple-system, "Segoe UI", Roboto, "Noto Sans", Ubuntu, Cantarell, sans-serif;
  letter-spacing: 0.01em;
}
a { color: var(--primary); }
a:focus-visible, button:focus-visible { outline: 2px solid var(--primary); outline-offset: 2px; }
main { max-width: 760px; margin: 0 auto; padding: 40px 16px 24px; }
header { display: flex; align-items: center; gap: 20px; margin-bottom: 28px; }
header img { width: 80px; height: 80px; border-radius: 22px; flex: none; box-shadow: 0 2px 10px rgba(0,0,0,.18); }
h1 { margin: 0; font-size: 2.1rem; line-height: 1.15; font-weight: 600; letter-spacing: 0; }
.tagline { margin: 4px 0 0; color: var(--muted); }
h2 { margin: 0 0 6px; font-size: 1.3rem; font-weight: 600; letter-spacing: 0; }
h3 { margin: 0 0 4px; font-size: 1.05rem; font-weight: 600; }
p { margin: 0 0 12px; }
.muted { color: var(--muted); }
.card { background: var(--card); border: 1px solid var(--line); border-radius: 16px; padding: 22px; margin-bottom: 16px; }
.lead { font-size: 1.05rem; margin-bottom: 28px; }
.address { display: flex; gap: 8px; align-items: stretch; margin: 14px 0 18px; }
.address code {
  flex: 1; min-width: 0; display: flex; align-items: center;
  background: var(--card-alt); border: 1px solid var(--line); border-radius: 12px;
  padding: 10px 14px; font: 600 1.05rem/1.3 ui-monospace, "Cascadia Mono", "Segoe UI Mono", "Roboto Mono", Menlo, Consolas, monospace;
  overflow-wrap: anywhere; user-select: all;
}
.address.small { flex-direction: column; align-items: flex-start; margin: 10px 0 14px; }
.address.small code { width: 100%; font-size: .92rem; font-weight: 500; }
.address.small button.copy { min-height: 40px; }
button.copy {
  flex: none; border: 0; border-radius: 20px; padding: 0 18px; min-height: 44px;
  background: var(--primary); color: var(--on-primary); font: inherit; font-weight: 600; cursor: pointer;
}
button.copy:hover { filter: brightness(1.08); }
ol.steps { margin: 0; padding: 0; list-style: none; counter-reset: step; }
ol.steps li { counter-increment: step; position: relative; padding: 0 0 12px 40px; }
ol.steps li::before {
  content: counter(step); position: absolute; left: 0; top: 0;
  width: 28px; height: 28px; border-radius: 50%; display: grid; place-items: center;
  background: var(--primary-container); color: var(--on-primary-container); font-weight: 700; font-size: .9rem;
}
.grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 16px; margin-bottom: 16px; }
.grid .card { margin: 0; display: flex; flex-direction: column; }
.platform { font-size: .9rem; color: var(--muted); margin-bottom: 12px; }
.buttons { display: flex; flex-wrap: wrap; gap: 8px; margin-top: auto; padding-top: 4px; }
a.button {
  display: inline-flex; align-items: center; min-height: 40px; padding: 0 16px; border-radius: 20px;
  text-decoration: none; font-weight: 600; font-size: .95rem;
  border: 1px solid var(--line); color: var(--primary);
}
a.button.primary { background: var(--primary); border-color: var(--primary); color: var(--on-primary); }
a.button:hover { filter: brightness(1.08); }
.contacts { list-style: none; margin: 12px 0 0; padding: 0; display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 8px; }
.contacts a {
  display: flex; align-items: center; gap: 12px; padding: 10px 14px; border-radius: 12px;
  background: var(--card-alt); color: var(--text); text-decoration: none; min-height: 56px;
}
.contacts a:hover { background: var(--chip); }
.contacts svg { flex: none; width: 22px; height: 22px; fill: var(--primary); }
.contacts span { display: block; min-width: 0; flex: 1; overflow: hidden; }
.contacts strong { display: block; font-weight: 600; }
.contacts small { display: block; color: var(--muted); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
footer { color: var(--muted); font-size: .9rem; text-align: center; padding: 12px 0 8px; }
footer a { color: var(--muted); }
@media (max-width: 520px) {
  main { padding-top: 24px; }
  header { gap: 14px; }
  header img { width: 60px; height: 60px; border-radius: 16px; }
  h1 { font-size: 1.7rem; }
  .card { padding: 18px; }
  .address { flex-direction: column; }
  button.copy { width: 100%; }
}
</style>
</head>
<body>
<main>
<header>
  <img src="{{IconPath}}" alt="" width="80" height="80">
  <div>
    <h1>Rekindle</h1>
    <p class="tagline">A self-hosted comic, manga and book server</p>
  </div>
</header>

<p class="lead">This is a Rekindle server. It holds a library of comics, manga and books, and you read them with the Rekindle apps for Windows, Linux and Android: browse the libraries, pick up where you left off on any device, and download for offline reading. There's nothing to read in the browser.</p>

<section class="card" aria-labelledby="connect">
  <h2 id="connect">Connect to this server</h2>
  <p class="muted">Give the app this address:</p>
  <div class="address">
    <code id="server-address">{{E(address)}}</code>
    <button class="copy" type="button" data-copy="server-address">Copy</button>
  </div>
  <ol class="steps">
    <li>Install the Rekindle app for your device from the downloads below.</li>
    <li>Open it, choose <strong>Add Server</strong>, paste the address above and choose <strong>Connect</strong>.</li>
    <li>Sign in with the username and password the server's administrator gave you.</li>
  </ol>
</section>

<h2 id="downloads">Get the apps</h2>
<p class="muted">Every release is on Gitea, and mirrored on GitHub.</p>
<div class="grid">
  <section class="card" aria-labelledby="desktop">
    <h3 id="desktop">Desktop</h3>
    <p class="platform">Windows and Linux</p>
    <p>An installer or a zip for Windows; an AppImage, Flatpak or zip for Linux.</p>
    <div class="buttons">
      <a class="button primary" href="{{GiteaReleases}}" rel="noopener noreferrer">Gitea Releases</a>
      <a class="button" href="{{GitHubReleases}}" rel="noopener noreferrer">GitHub Releases</a>
    </div>
  </section>
  <section class="card" aria-labelledby="android">
    <h3 id="android">Android</h3>
    <p class="platform">Phones and tablets</p>
    <p>Add this repository to <a href="https://f-droid.org" rel="noopener noreferrer">F-Droid</a> to install Rekindle and get its updates:</p>
    <div class="address small">
      <code id="fdroid-repo">{{FDroidRepo}}</code>
      <button class="copy" type="button" data-copy="fdroid-repo">Copy</button>
    </div>
    <p class="muted">Or install the APK from the releases:</p>
    <div class="buttons">
      <a class="button primary" href="{{GiteaReleases}}" rel="noopener noreferrer">Gitea Releases</a>
      <a class="button" href="{{GitHubReleases}}" rel="noopener noreferrer">GitHub Releases</a>
    </div>
  </section>
</div>
{{contactSection}}
<footer>
  Rekindle{{versionText}} ·
  <a href="{{Wiki}}" rel="noopener noreferrer">Documentation</a> ·
  <a href="{{GiteaRepo}}" rel="noopener noreferrer">Source on Gitea</a> ·
  <a href="{{GitHubRepo}}" rel="noopener noreferrer">GitHub mirror</a>
</footer>
</main>
<script nonce="{{E(nonce)}}">
(function () {
  // The server can't always tell how the browser reached it (a reverse proxy
  // may terminate TLS), but the browser knows.
  var el = document.getElementById('server-address');
  if (el && /^https?:$/.test(location.protocol)) {
    el.textContent = (location.origin + location.pathname).replace(/\/+$/, '');
  }

  function fallbackCopy(text) {
    var area = document.createElement('textarea');
    area.value = text;
    area.setAttribute('readonly', '');
    area.style.position = 'fixed';
    area.style.opacity = '0';
    document.body.appendChild(area);
    area.select();
    var ok = false;
    try { ok = document.execCommand('copy'); } catch (e) {}
    document.body.removeChild(area);
    return ok;
  }

  document.querySelectorAll('button[data-copy]').forEach(function (button) {
    button.addEventListener('click', function () {
      var target = document.getElementById(button.getAttribute('data-copy'));
      if (!target) return;
      var text = target.textContent.trim();
      function done(ok) {
        button.textContent = ok ? 'Copied' : 'Select and copy';
        setTimeout(function () { button.textContent = 'Copy'; }, 2000);
      }
      // The clipboard API needs https or localhost; plain http on a LAN doesn't have it.
      if (navigator.clipboard && window.isSecureContext) {
        navigator.clipboard.writeText(text).then(function () { done(true); },
          function () { done(fallbackCopy(text)); });
      } else {
        done(fallbackCopy(text));
      }
    });
  });
})();
</script>
</body>
</html>
""";
    }

    private const string MailIcon =
        """<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M20 4H4a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2zm0 4-8 5-8-5V6l8 5 8-5v2z"/></svg>""";

    private const string LinkIcon =
        """<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3.9 12a3.1 3.1 0 0 1 3.1-3.1h4V7H7a5 5 0 0 0 0 10h4v-1.9H7A3.1 3.1 0 0 1 3.9 12zM8 13h8v-2H8v2zm9-6h-4v1.9h4a3.1 3.1 0 0 1 0 6.2h-4V17h4a5 5 0 0 0 0-10z"/></svg>""";

    private static string RenderContacts(IReadOnlyList<ContactLink> contacts)
    {
        var items = new StringBuilder();
        foreach (var link in contacts)
        {
            // rel="me" lets a Mastodon profile verify it links back here.
            var rel = link.IsEmail ? "" : " rel=\"me noopener noreferrer\"";
            items.Append($"""
    <li><a href="{E(link.Href)}"{rel}>{(link.IsEmail ? MailIcon : LinkIcon)}<span><strong>{E(link.Name)}</strong><small title="{E(link.Detail)}">{E(link.Detail)}</small></span></a></li>

""");
        }

        return $"""
<section class="card" aria-labelledby="contact">
  <h2 id="contact">Contact the administrator</h2>
  <p class="muted">Need an account, or something isn't working? You can reach whoever runs this server here.</p>
  <ul class="contacts">
{items}  </ul>
</section>

""";
    }
}
