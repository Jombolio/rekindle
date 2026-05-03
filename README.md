# Rekindle

Self-hosted comic, manga, and book reader.

> **Disclaimer:** Rekindle is intended for use with content you own or have the legal right to access. Do not use this software to store, distribute, or access copyrighted material without authorisation. The developers are not responsible for any misuse of this software.
Point the Rekindle Server at a folder of archives (CBZ, CBR, EPUB, MOBI, PDF) and read or download them from any device running the Rekindle Client.

<img width="1277" height="371" alt="Screenshot_20260420_215357" src="https://github.com/user-attachments/assets/0f389771-0a4d-4c71-897b-85dcdccb26d6" />

---

## Table of Contents

- [Supported Formats](#supported-formats)
- [Client Setup](#client-setup)
  - [Linux](#linux-1)
  - [Windows](#windows-1)
  - [Android](#android)
- [Server Setup](#server-setup)
  - [Linux](#linux)
  - [Windows](#windows)
  - [Configuration](#configuration)
  - [HTTPS](#https)
  - [First-time Setup](#first-time-setup)
- [Connecting to the Server](#connecting-to-the-server)
- [Metadata APIs](#metadata-apis)
  - [Overview](#overview)
  - [ComicVine](#comicvine)
  - [MyAnimeList](#myanimelist)
  - [AniList](#anilist)
  - [Configuring API Keys](#configuring-api-keys)
- [Building from Source](#building-from-source)

---

## Supported Formats

| Format | Extension | Notes |
|--------|-----------|-------|
| Comic Book ZIP | `.cbz` | |
| Comic Book RAR | `.cbr` | |
| EPUB | `.epub` | Rendered natively, no WebView |
| MOBI | `.mobi` | |
| PDF | `.pdf` | |

### Library Types

| Type | Reading Direction Default |
|------|--------------------------|
| Comics | Left-to-right |
| Manga | Right-to-left |
| Books | Left-to-right |

The reading direction can be toggled at anytime while browsing.

---

## Client Setup

Download the latest client release from the [Releases page](https://github.com/Jombolio/rekindle/releases/tag/Pre-release).

### Linux

1. Download and extract `Rekindle-v0.8-linux-x64.zip`
2. Make the binary executable:
   ```bash
   chmod +x rekindle
   ```
3. Run it:
   ```bash
   ./rekindle
   ```

### Windows

1. Download and extract `Rekindle-v0.8-windows-x64.zip`.
2. Run `rekindle.exe`.

> Windows may show a SmartScreen warning on first launch because the binary is not code-signed. Click **More info → Run anyway**.

### Android

Download and install the `.apk` from the [Releases page](https://github.com/Jombolio/rekindle/releases/tag/Pre-release).

> You will need to allow installation from unknown sources. On most devices: **Settings → Apps → Special app access → Install unknown apps**.

**Requirements:** Android 8.0 (API 26) or later.

---

## Connecting to the Server

1. Open the Rekindle Client.
2. Enter your server URL. (e.g. `http://192.168.1.10:8080`)
3. If no admin account exists yet, you will be prompted for the setup token printed in the server console.
4. Create your admin account and log in.
5. Go to **Admin → Libraries**, create a library, point it at a folder of archives on the server machine, and trigger a scan.

---

## Server Setup

Download the latest server release from the [Releases page](https://github.com/Jombolio/rekindle/releases/tag/Pre-release).

### Linux

1. Download and extract `RekindleServer-v0.8-linux-x64.zip`
2. Make the binary executable:
   ```bash
   chmod +x Rekindle.Server
   ```
3. Run it:
   ```bash
   ./Rekindle.Server
   ```

The server listens on `http://0.0.0.0:8080` by default.

### Windows

1. Download and extract `RekindleServer-v0.8-windows-x64.zip`
2. Run `Rekindle.Server.exe`

The server listens on `http://0.0.0.0:8080` by default.

### Configuration

Edit `appsettings.json` in the same directory as the server binary before first launch.

| Key | Default | Description |
|-----|---------|-------------|
| `Rekindle.DataPath` | `data` | Directory where your media libraries are stored |
| `Rekindle.CachePath` | `data/cache` | Directory for extracted page cache |
| `Rekindle.CacheMaxSizeBytes` | `10737418240` | Maximum cache size in bytes (default 10 GB) |
| `Jwt.Secret` | *(auto-generated)* | JWT signing secret — generated and saved to `data/jwt_secret.key` on first run. Set manually to share a secret across multiple instances. |
| `Urls` | `http://0.0.0.0:8080` | Bind address and port |

**Example — changing the port and pointing at an existing media folder:**
```json
{
  "Rekindle": {
    "DataPath": "/mnt/media/rekindle",
    "CachePath": "/mnt/media/rekindle-cache",
    "CacheMaxSizeBytes": 21474836480
  },
  "Urls": "http://0.0.0.0:9000"
}
```

### HTTPS

The server speaks plain HTTP by default. Two ways to add TLS:

#### Option A — Caddy reverse proxy (recommended)

[Caddy](https://caddyserver.com) obtains and renews Let's Encrypt certificates automatically.

1. Install Caddy and point your domain's DNS at the server machine.
2. Create a `Caddyfile`:
   ```
   your.domain.com {
       reverse_proxy localhost:8080 {
           # Raise transport timeouts so large archive uploads don't get cut off.
           transport http {
               read_buffer  32KiB
               write_timeout 30m
               dial_timeout  30s
           }
       }
   }
   ```
3. Run Caddy:
   ```bash
   caddy run --config Caddyfile
   ```

Caddy handles port 80/443 and forwards traffic to Rekindle on 8080. No certificate management required.

> For LAN-only use without a domain, use a self-signed certificate or keep plain HTTP and access the server by IP.

#### Option A2 — Nginx reverse proxy

If you prefer Nginx, set `client_max_body_size` and extend the proxy timeouts. The default body limit (1 MB) and read timeout (60 s) will cause large uploads to fail with a connection reset error.

```nginx
server {
    listen 443 ssl;
    server_name your.domain.com;

    # Required: allow large archive uploads (match the Kestrel 4 GB limit).
    client_max_body_size 4G;

    # Required: give the upload enough time to transfer.
    proxy_read_timeout    1800;
    proxy_send_timeout    1800;
    proxy_connect_timeout   30;

    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Disable request buffering so Kestrel receives the stream directly
        # instead of Nginx buffering the whole file to disk first.
        proxy_request_buffering off;
    }
}
```

> **Without `client_max_body_size 4G`** Nginx drops the TCP connection mid-upload and the client sees `Connection reset by peer (errno 104)`. This is the most common upload error when running behind Nginx.

#### Option B — Kestrel direct TLS

If you already have a PEM certificate and key, configure Kestrel in `appsettings.json`:

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

Place `cert.pem` and `key.pem` in the same directory as the server binary, then restart.

---

### First-time Setup

On first launch with no admin account, the server prints a one-time setup token to the console:

```
════════════════════════════════════════════════════════
  REKINDLE FIRST-TIME SETUP
  No admin account exists. Use the token below to
  complete setup via POST /api/auth/setup.
  Setup token: <token>
  This token is one-time and invalidated after use.
════════════════════════════════════════════════════════
```

Use the Rekindle Client to complete setup — it will prompt for this token on first connection.

---

## Metadata APIs

Rekindle can fetch "About" metadata for your manga and comic series — synopsis, genres, score, publication year, and status — directly from third-party databases. Metadata is stored locally in the server database after the first scrape.

Only administrators can trigger a scrape or configure API keys. Readers can view the cached result.

### Overview

| Source | Used for | Key required? | Rate limit |
|--------|----------|---------------|------------|
| [ComicVine](#comicvine) | Comics **only** | Yes | 200 req / resource / hour |
| [MyAnimeList](#myanimelist) | Manga **only** | Yes | Varies by endpoint |
| [AniList](#anilist) | Manga **only** (fallback) | No | 30 req / min (Rekindle-enforced) |

Source routing is **strict and exclusive** — each library type uses only its designated source(s):

- **Comic libraries** → ComicVine only. MAL and AniList are never queried. No key = no metadata.
- **Manga libraries** → MyAnimeList first (if a key is configured), then AniList as an automatic fallback.
- **Other library types** → same as manga.

ComicVine is never used for manga. MAL and AniList are never used for comics.

### ComicVine

[ComicVine](https://comicvine.gamespot.com) is a community-run comic database covering Western comics, graphic novels, and more.

**Rate limits:** 200 requests per resource per hour. ComicVine also uses velocity detection — too many rapid requests will result in a temporary block. Rekindle enforces a minimum 1-second gap between requests to stay within the velocity limit.

#### Getting a ComicVine API key

1. Create a free account at [comicvine.gamespot.com](https://comicvine.gamespot.com).
2. Go to **[comicvine.gamespot.com/api](https://comicvine.gamespot.com/api)**.
3. Your API key is displayed at the top of the page under **"Your API Key"**. Copy it.
4. Add it in the Rekindle Admin Panel under **Admin → APIs → ComicVine API Key**.

> Keep your API key private. It is stored securely on the server and never sent to clients.

### MyAnimeList

[MyAnimeList (MAL)](https://myanimelist.net) is the most widely used anime and manga database. Rekindle uses its v2 REST API to fetch manga series information.

**Rate limits:** MAL rate limits vary. In practice, occasional scraping of individual series is well within the allowed usage. Avoid bulk-scraping large libraries in rapid succession.

#### Getting a MAL Client ID

1. Log into your account at [myanimelist.net](https://myanimelist.net). Create one if you don't have one — it's free.
2. Go to **[myanimelist.net/apiconfig](https://myanimelist.net/apiconfig)**.
3. Click **Create ID**.
4. Fill in the required fields:
   - **App Name:** `Rekindle` (or any name you like)
   - **App Type:** `other`
   - **App Description:** A brief description (e.g. "Personal self-hosted reader")
   - **App Redirect URL:** `http://localhost` (a placeholder is required even for non-OAuth use)
5. Accept the API License Agreement and click **Submit**.
6. Your **Client ID** is shown on the next page. Copy it.
7. Add it in the Rekindle Admin Panel under **Admin → APIs → MyAnimeList → MAL Client ID**.

> MAL Client IDs are for read-only public data access. Rekindle only ever makes `GET` requests; it does not post to or modify your MAL account in any way.

### AniList

[AniList](https://anilist.co) is a modern anime and manga tracking site with a public GraphQL API. Rekindle uses it as a fallback when no MAL key is configured, or when MAL returns no result.

**No registration is required.** The public AniList API is freely accessible without an account or key.

**Rate limits:** AniList uses a burst limiter. Rekindle enforces a sliding-window cap of **30 requests per minute** to stay safely within AniList's limits. Requests that exceed this are silently dropped rather than queued, so back-to-back scrape operations on many series should be spaced a few seconds apart.

### Configuring API Keys

API keys are set once per server instance and apply to all users. They are **write-only** from the admin UI — you can update a key but cannot read it back once saved.

#### Via the Admin Panel (recommended)

1. Log in as an admin and open the client.
2. Navigate to **Admin Panel → APIs** tab.
3. Enter the key(s) in the relevant field(s) and click **Save API Keys**.
4. A "Key set" badge will appear next to each configured source.

#### Scraping metadata for a series

Once at least one API key is configured (or for manga, where AniList requires no key):

1. Browse to any **manga or comic series** (a folder/series view, not an individual issue).
2. If you are an admin, a **refresh icon** (↻) appears in the "About" card at the top of the chapter list.
3. Tap it to trigger a scrape. Rekindle fetches fresh data and compares it with what is already stored:

| Result | What happens |
|--------|-------------|
| **No prior metadata** | Data is written immediately and displayed. |
| **Matches stored data** | No write is performed. A "Metadata is already up to date" message is shown. |
| **Conflicts with stored data** | A **diff dialog** appears showing the changed fields side-by-side. Choose **"Keep existing"** to leave the stored data unchanged, or **"Use new data"** to overwrite with the fresh result. |

This means re-scraping a series never silently overwrites data you may have manually adjusted, and avoids unnecessary database writes when nothing has changed.

---

## Building from Source

**Requirements:** Flutter SDK, .NET 10 SDK

### Server

```bash
cd server
dotnet run --project Rekindle.Server
```

For a release build:

```bash
# Linux
dotnet publish Rekindle.Server /p:PublishProfile=linux-x64

# Windows
dotnet publish Rekindle.Server /p:PublishProfile=win-x64
```

Output goes to `Rekindle.Server/bin/publish/{platform}/` and contains only five files:

```
Rekindle.Server          (or Rekindle.Server.exe on Windows)
libe_sqlite3.so          (native SQLite — libsqlite3.dll on Windows)
pdfium.so                (native PDF renderer — pdfium.dll on Windows)
appsettings.json
LICENSE
```

### Client

```bash
cd client
flutter run -d linux    # Linux
flutter run -d windows  # Windows (must build on a Windows machine)
flutter run             # Android (device or emulator connected)
```

For release builds, use `--obfuscate` and `--split-debug-info` to strip embedded build-machine paths from the binary:

```bash
flutter build linux   --release --obfuscate --split-debug-info=symbols/
flutter build windows --release --obfuscate --split-debug-info=symbols/
flutter build apk     --release --obfuscate --split-debug-info=symbols/
```

Keep the generated `symbols/` directory — it is required to decode stack traces from crash reports.
