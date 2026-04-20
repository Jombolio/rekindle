# Rekindle

Self-hosted comic, manga, and book reader.
Point the Rekindle Server at a folder of archives (CBZ, CBR, EPUB, MOBI, PDF) and read or download them from any device running the Rekindle Client.

<img width="1277" height="371" alt="Screenshot_20260420_215357" src="https://github.com/user-attachments/assets/0f389771-0a4d-4c71-897b-85dcdccb26d6" />

---

## Table of Contents

- [Supported Formats](#supported-formats)
- [Server Setup](#server-setup)
  - [Linux](#linux)
  - [Windows](#windows)
  - [Configuration](#configuration)
  - [First-time Setup](#first-time-setup)
- [Client Setup](#client-setup)
  - [Linux](#linux-1)
  - [Windows](#windows-1)
  - [Android](#android)
- [Connecting to the Server](#connecting-to-the-server)
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
| `Rekindle.CachePath` | `cache` | Directory for extracted page cache |
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

1. Download and extract `Rekindle-v0.8-windows-x64.zip`
2. Run `rekindle.exe`

> Windows may show a SmartScreen warning on first launch because the binary is not code-signed. Click **More info → Run anyway**.

### Android

Download and install the `.apk` from the [Releases page](https://github.com/Jombolio/rekindle/releases/tag/Pre-release).

> You will need to allow installation from unknown sources. On most devices: **Settings → Apps → Special app access → Install unknown apps**.

**Requirements:** Android 8.0 (API 26) or later.

---

## Connecting to the Server

1. Open the Rekindle Client
2. Enter your server URL (e.g. `http://192.168.1.10:8080`)
3. If no admin account exists yet, you will be prompted for the setup token printed in the server console
4. Create your admin account and log in
5. Go to **Admin → Libraries**, create a library, point it at a folder of archives on the server machine, and trigger a scan

---

## Building from Source

**Requirements:** Flutter SDK, .NET 10 SDK

### Server

```bash
cd server
dotnet run --project Rekindle.Server
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
