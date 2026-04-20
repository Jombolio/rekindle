# Rekindle

Self-hosted comic, manga, and book reader. Point it at a folder of CBZ/CBR archives or EPUBs and read them from any device.

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
| `Jwt.Secret` | *(required)* | Set a long random string before first run |
| `Urls` | `http://0.0.0.0:8080` | Bind address and port |

## Client

**Requirements:** Flutter SDK

```bash
cd client
flutter run -d linux    # Linux
flutter run -d windows  # Windows (must build on Windows)
flutter run             # Android (device/emulator connected)
```

On first launch, enter your server URL and log in.
