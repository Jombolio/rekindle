# Configuration

The server is configured by editing `appsettings.json` in the same directory as the binary. Changes take effect on the next restart, except `Rekindle.Contacts` and `Rekindle.LandingTheme`, which apply straight away.

---

## All options

| Key | Default | Description |
|-----|---------|-------------|
| `Rekindle.DataPath` | `data` | Where the server stores its SQLite database, JWT secret, and other runtime files |
| `Rekindle.CachePath` | `data/cache` | Where extracted page images are cached. Can be on a separate drive from the database |
| `Rekindle.CacheMaxSizeBytes` | `10737418240` | Maximum page cache size in bytes (default 10 GB). Oldest entries are evicted when the limit is reached |
| `Rekindle.UpdateSource` | `https://git.jombo.uk/Jombo/rekindle` | The Gitea repository `--update` and `--dev-update` install releases from. See [Updating](Installing-the-Server#updating) |
| `Rekindle.UpdateFallbackSource` | `https://github.com/Jombolio/rekindle` | Used only when `UpdateSource` can't be reached. Gitea and GitHub repositories both work. Set it to `""` to turn the fallback off |
| `Rekindle.Contacts` | `[]` | Contact links shown on the server's [landing page](#contact-links-on-the-landing-page), so readers know how to reach you. Each entry has a `Name` and a `Url`. Changes apply without a restart |
| `Rekindle.LandingTheme` | `System` | Colour scheme of the landing page: `System` follows each visitor's light or dark setting, `Light` or `Dark` always uses that one. Changes apply without a restart |
| `Jwt.Secret` | *(auto-generated)* | JWT signing secret. Auto-generated and written to `data/jwt_secret.key` on first run. Set this manually if you run multiple server instances behind a load balancer |
| `Urls` | `http://0.0.0.0:8080` | The address and port Kestrel binds to. Accepts multiple values separated by semicolons |

---

## Examples

### Change the port

```json
{
  "Urls": "http://0.0.0.0:9000"
}
```

### Point at an existing media folder on a separate drive

```json
{
  "Rekindle": {
    "DataPath": "/mnt/media/rekindle/data",
    "CachePath": "/mnt/media/rekindle/cache"
  }
}
```

### Increase the cache size to 25 GB

```json
{
  "Rekindle": {
    "CacheMaxSizeBytes": 26843545600
  }
}
```

### Contact links on the landing page

Opening the server's address in a web browser (for example `http://192.168.1.10:8080` or `https://rekindle.yourdomain.com`) shows a landing page. It says what Rekindle is, where to download the apps, and shows the server's own address to copy into them.

List ways to reach you under `Rekindle.Contacts` and the page shows them in a **Contact the administrator** section. With no entries the section isn't shown.

```json
{
  "Rekindle": {
    "Contacts": [
      { "Name": "Discord", "Url": "https://discord.gg/your-invite" },
      { "Name": "Email", "Url": "mailto:admin@example.com" },
      { "Name": "Matrix", "Url": "https://matrix.to/#/@you:example.org" },
      { "Name": "Mastodon", "Url": "https://mastodon.social/@you" },
      { "Name": "Website", "Url": "https://example.com" }
    ]
  }
}
```

- `Url` must be an `http://`, `https://` or `mailto:` link. A bare email address such as `admin@example.com` is treated as `mailto:`. Anything else (for example `javascript:` or a `matrix:` link) is left off the page and a warning is written to the server log. For Matrix, use a `https://matrix.to/#/...` link.
- `Name` is optional. Without it the page shows the site's host name, or "Email" for an email address.
- Entries appear in the order you list them, and any name works, so you can add whatever suits you.
- The page picks up edits to `appsettings.json` straight away; no restart is needed.
- Web links carry `rel="me"`, so a Mastodon profile that links back to your server can show it as verified.

### Landing page theme

The landing page follows each visitor's light or dark setting. To always show it dark (or light), set `LandingTheme`:

```json
{
  "Rekindle": {
    "LandingTheme": "Dark"
  }
}
```

Accepted values are `System` (the default), `Light` and `Dark`, in any case. Any other value is ignored with a warning in the server log, and the page follows the visitor's setting.

### Bind to localhost only (if behind a reverse proxy on the same machine)

```json
{
  "Urls": "http://127.0.0.1:8080"
}
```

---

## Notes

- All paths can be absolute or relative. Relative paths are resolved from the server binary's working directory.
- If `DataPath` or `CachePath` do not exist, the server creates them on first run.
- The JWT secret file (`data/jwt_secret.key`) is generated once and reused on subsequent starts. Do not delete it — doing so will invalidate all existing sessions and log everyone out.

---

## See also

- [HTTPS](HTTPS) — TLS configuration for Kestrel or a reverse proxy
- [Installing the Server](Installing-the-Server) — systemd and Windows Service setup
