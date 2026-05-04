# Building from Source

**Requirements:**
- [.NET 10 SDK](https://dotnet.microsoft.com/download) (server)
- [Flutter SDK](https://flutter.dev/docs/get-started/install) (client)

---

## Server

### Development run

```bash
cd server
dotnet run --project Rekindle.Server
```

### Release build

```bash
# Linux self-contained binary
dotnet publish Rekindle.Server /p:PublishProfile=linux-x64

# Windows self-contained binary
dotnet publish Rekindle.Server /p:PublishProfile=win-x64
```

Output goes to `Rekindle.Server/bin/publish/{platform}/` and contains five files:

```
Rekindle.Server          (Rekindle.Server.exe on Windows)
libe_sqlite3.so          (libsqlite3.dll on Windows)
pdfium.so                (pdfium.dll on Windows)
appsettings.json
LICENSE
```

The build is framework-dependent (requires the .NET 10 runtime on the target machine) but single-file, all managed assemblies are bundled into the binary.

---

## Client

### Development run

```bash
cd desktop
flutter run -d linux      # Linux desktop
flutter run -d windows    # Windows desktop (must build on Windows)
flutter run               # Android (device or emulator connected)
```

### Release build

Use `--obfuscate` and `--split-debug-info` to strip build-machine paths from the binary:

```bash
flutter build linux   --release --obfuscate --split-debug-info=symbols/
flutter build windows --release --obfuscate --split-debug-info=symbols/
flutter build apk     --release --obfuscate --split-debug-info=symbols/
```

> Keep the generated `symbols/` directory. It is required to decode stack traces from crash reports. Do not distribute it.

### Output locations

| Platform | Output |
|----------|--------|
| Linux | `build/linux/x64/release/bundle/` |
| Windows | `build/windows/x64/runner/Release/` |
| Android APK | `build/app/outputs/flutter-apk/app-release.apk` |
