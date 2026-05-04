# Rekindle

Rekindle is a self-hosted comic, manga, and book server with clients for Linux, Windows, and Android.

Run the server on any machine that holds your archive files. Connect from any device running the client, browse your libraries, read in the browser-free native reader, and download issues for offline use. Multiple users are supported, each with their own reading progress and permission level.

> **Disclaimer:** Rekindle is intended for use with content you own or have the legal right to access. The developers are not responsible for any misuse.

<img width="1277" height="371" alt="Rekindle screenshot" src="https://github.com/user-attachments/assets/0f389771-0a4d-4c71-897b-85dcdccb26d6" />

---

## Table of Contents

- [Supported Formats](#supported-formats)
- [Client Setup](#client-setup)
- [Server Setup](#server-setup)
  - [Configuration](#configuration)
  - [HTTPS](#https)
  - [First-time Setup](#first-time-setup)
- [Connecting to the Server](#connecting-to-the-server)
- [Metadata APIs](#metadata-apis)
- [Building from Source](#building-from-source)

---

## Supported Formats

| Format | Extension |
|--------|-----------|
| Comic Book ZIP | `.cbz` |
| Comic Book RAR | `.cbr` |
| EPUB | `.epub` |
| MOBI | `.mobi` |
| PDF | `.pdf` |

### Library Types

| Type | Default reading direction |
|------|--------------------------|
| Comics | Left-to-right |
| Manga | Right-to-left |
| Books | Left-to-right |

Reading direction can be toggled at any time inside the reader.

---

## Client Setup

Download the latest release from the [Releases page](https://github.com/Jombolio/rekindle/releases/tag/Pre-release).

### Linux

```bash
chmod +x rekindle
./rekindle
```

### Windows

Run `rekindle.exe`.

> Windows may show a SmartScreen warning on first launch because the binary is unsigned. Click **More info → Run anyway**.

### Android

Install the `.apk` from the [Releases page](https://github.com/Jombolio/rekindle/releases/tag/Pre-release).

> Allow installation from unknown sources: **Settings → Apps → Special app access → Install unknown apps**.

Requires Android 8.0 (API 26) or later.

---

## Server Setup

Download the latest server release from the [Releases page](https://github.com/Jombolio/rekindle/releases/tag/Pre-release).

### Linux

```bash
chmod +x Rekindle.Server
./Rekindle.Server
```

### Windows

Run `Rekindle.Server.exe`.

The server listens on `http://0.0.0.0:8080` by default on both platforms.

---

### Configuration

Edit `appsettings.json` next to the server binary before first launch.

| Key | Default | Description |
|-----|---------|-------------|
| `Rekindle.DataPath` | `data` | Database and runtime files |
| `Rekindle.CachePath` | `data/cache` | Extracted page cache |
| `Rekindle.CacheMaxSizeBytes` | `10737418240` | Max cache size (default 10 GB) |
| `Jwt.Secret` | *(auto-generated)* | JWT signing secret — written to `data/jwt_secret.key` on first run |
| `Urls` | `http://0.0.0.0:8080` | Bind address and port |

**Example:**
```json
{
  "Rekindle": {
    "DataPath": "/mnt/media/rekindle",
    "CachePath": "/mnt/media/rekindle-cache"
  },
  "Urls": "http://0.0.0.0:9000"
}
```

---

### HTTPS

The server speaks plain HTTP by default. Two options to add TLS:

#### Option A — Caddy (recommended)

[Caddy](https://caddyserver.com) handles certificates automatically.

```
your.domain.com {
    reverse_proxy localhost:8080 {
        transport http {
            read_buffer  32KiB
            write_timeout 30m
            dial_timeout  30s
        }
    }
}
```

```bash
caddy run --config Caddyfile
```

#### Option B — Nginx

Set `client_max_body_size` and extend proxy timeouts — the defaults will cut off large archive uploads.

```nginx
server {
    listen 443 ssl;
    server_name your.domain.com;

    client_max_body_size 4G;
    proxy_read_timeout    1800;
    proxy_send_timeout    1800;
    proxy_connect_timeout   30;

    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_request_buffering off;
    }
}
```

#### Option C — Kestrel direct TLS

```json
{
  "Urls": "https://0.0.0.0:8443",
  "Kestrel": {
    "Endpoints": {
      "Https": {
        "Url": "https://0.0.0.0:8443",
        "Certificate": {
          "Path": "cert.pem",
          "KeyPath": "key.pem"
        }
      }
    }
  }
}
```

Place `cert.pem` and `key.pem` alongside the binary.

---

### First-time Setup

On first launch, the server prints a one-time setup token:

```
════════════════════════════════════════════════════════
  REKINDLE FIRST-TIME SETUP
  Setup token: <token>
════════════════════════════════════════════════════════
```

The client will prompt for this token when you connect for the first time.

---

## Connecting to the Server

1. Open the Rekindle client.
2. Enter your server URL — e.g. `http://192.168.1.10:8080`.
3. On first connection, enter the setup token from the server console to create the admin account.
4. Go to **Admin → Libraries**, create a library pointing at a folder of archives on the server machine, and trigger a scan.

---

## Metadata APIs

Rekindle can automatically fetch an "About" card for each manga or comic series — synopsis, genres, score, year, and status — from third-party databases. Data is stored in the local server database after the first scrape and is never re-fetched silently; if a rescrape returns different data, a diff dialog lets you choose which version to keep.

Only admins can trigger scrapes or configure API keys. All users can view cached metadata.

### Sources

| Source | Used for | Key required? | Rate limit |
|--------|----------|---------------|------------|
| [ComicVine](https://comicvine.gamespot.com) | Comics only | Yes | 200 req / resource / hour |
| [MyAnimeList](https://myanimelist.net) | Manga only | Yes | Varies |
| [AniList](https://anilist.co) | Manga only (fallback) | No | 30 req / min |

Routing is strict: comic libraries only ever query ComicVine; manga libraries only ever query MAL then AniList. The sources are never mixed.

### Getting a ComicVine API Key

1. Create a free account at [comicvine.gamespot.com](https://comicvine.gamespot.com).
2. Go to **[comicvine.gamespot.com/api](https://comicvine.gamespot.com/api)**.
3. Copy the key shown under **"Your API Key"**.
4. Paste it in the client under **Admin Panel → APIs → ComicVine API Key**.

### Getting a MyAnimeList Client ID

1. Log in at [myanimelist.net](https://myanimelist.net).
2. Go to **[myanimelist.net/apiconfig](https://myanimelist.net/apiconfig)** and click **Create ID**.
3. Fill in the form — App Type: `other`, Redirect URL: `http://localhost`.
4. Copy the Client ID from the next page.
5. Paste it in the client under **Admin Panel → APIs → MAL Client ID**.

### Scraping metadata

1. Open any manga or comic series (the folder/series view, not an individual issue).
2. Tap the **↻** icon in the About card (admin only).

| Result | What happens |
|--------|-------------|
| No prior metadata | Written immediately and displayed. |
| Matches stored data | No write performed; "already up to date" message shown. |
| Conflicts with stored data | Diff dialog appears — choose to keep existing or use new data. |

---

## Building from Source

**Requirements:** Flutter SDK, .NET 10 SDK

### Server

```bash
cd server
dotnet run --project Rekindle.Server
```

Release build:

```bash
dotnet publish Rekindle.Server /p:PublishProfile=linux-x64   # Linux
dotnet publish Rekindle.Server /p:PublishProfile=win-x64     # Windows
```

Output in `Rekindle.Server/bin/publish/{platform}/`:

```
Rekindle.Server        (Rekindle.Server.exe on Windows)
libe_sqlite3.so        (libsqlite3.dll on Windows)
pdfium.so              (pdfium.dll on Windows)
appsettings.json
LICENSE
```

### Client

```bash
cd client
flutter run -d linux      # Linux desktop
flutter run -d windows    # Windows desktop
flutter run               # Android (device or emulator)
```

Release builds:

```bash
flutter build linux   --release --obfuscate --split-debug-info=symbols/
flutter build windows --release --obfuscate --split-debug-info=symbols/
flutter build apk     --release --obfuscate --split-debug-info=symbols/
```

Keep the `symbols/` directory — it is needed to decode crash stack traces.
