# Rekindle

Self-hosted comic, manga, and book reader. 
Point the Rekindle Server to a folder of book archives (such as CBZs, CBRs, EPUBs, MOBIs or PDFs) and read/download them from any device running the Rekindle Client.

## Structure

| Folder | What it is |
|--------|------------|
| `server/` | .NET 10 backend |
| `client/` | Flutter desktop client (Linux & Windows) |
| `android/` | Flutter Android client |

## Server

**Requirements:** .NET 10 runtime

```bash
cd server
dotnet run --project Rekindle.Server
```

The server listens on `http://0.0.0.0:8080` by default.

Edit `Rekindle.Server/appsettings.json` to configure:

| Key | Default | Description |
|-----|---------|-------------|
| `Rekindle.DataPath` | `data` | Where your media libraries live |
| `Rekindle.CachePath` | `cache` | Extracted page cache |
| `Rekindle.CacheMaxSizeBytes` | `10737418240` (10 GB) | Cache size limit |
| `Jwt.Secret` | *(auto-generated)* | Generated and persisted to `data/jwt_secret.key` on first run |
| `Urls` | `http://0.0.0.0:8080` | Bind address and port |

## Client

**Requirements:** Flutter SDK

```bash
cd client
flutter run -d linux    # Linux
flutter run -d windows  # Windows (must build on Windows)
flutter run             # Android (device/emulator connected)
```

For release builds, use `--obfuscate` and `--split-debug-info` to strip embedded build-machine paths from the binary:

```bash
flutter build linux --release --obfuscate --split-debug-info=symbols/
flutter build windows --release --obfuscate --split-debug-info=symbols/  # on Windows
flutter build apk --release --obfuscate --split-debug-info=symbols/
```

Keep the generated `symbols/` directory — it is required to decode stack traces from crash reports.

On first launch, enter your server URL and log in.
