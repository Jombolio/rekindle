# Installing the Server

The Rekindle Server is a single self-contained binary. It stores its database, cache, and configuration in a `data/` folder next to the binary.

---

## Linux

### 1. Download

Grab the latest `RekindleServer-linux-x64.zip` from the [Releases page](https://github.com/Jombolio/rekindle/releases).

### 2. Extract

```bash
unzip RekindleServer-linux-x64.zip -d RekindleServer
cd RekindleServer
```

### 3. Make the binary executable

```bash
chmod +x Rekindle.Server
```

### 4. Run

```bash
./Rekindle.Server
```

The server starts on `http://0.0.0.0:8080` by default and creates its `data/` folder on first launch.

### Running as a systemd service (optional)

To keep the server running in the background and start it automatically on boot, create a service unit.

Create `/etc/systemd/system/rekindle.service`:

```ini
[Unit]
Description=Rekindle Server
After=network.target

[Service]
Type=simple
User=YOUR_USER
WorkingDirectory=/opt/rekindle
ExecStart=/opt/rekindle/Rekindle.Server
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Replace `YOUR_USER` with the user account that should own the process, and update `WorkingDirectory` / `ExecStart` to wherever you extracted the server.

Enable and start it:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now rekindle
sudo systemctl status rekindle
```

View logs:

```bash
journalctl -u rekindle -f
```

---

## Windows

### 1. Download

Grab the latest `RekindleServer-windows-x64.zip` from the [Releases page](https://github.com/Jombolio/rekindle/releases).

### 2. Extract

Right-click the zip → **Extract All**, or use your preferred tool. Place the extracted folder wherever you like (e.g. `C:\RekindleServer`).

### 3. Run

Double-click `Rekindle.Server.exe`, or run it from a terminal:

```powershell
.\Rekindle.Server.exe
```

The server starts on `http://0.0.0.0:8080` by default.

> **Windows Firewall:** On first launch, Windows may ask whether to allow network access. Click **Allow access** so clients on your network can connect.

### Running as a Windows Service (optional)

To run Rekindle in the background without keeping a terminal open, use the built-in `sc` tool.

Open an **elevated** (Administrator) Command Prompt:

```cmd
sc create Rekindle binPath= "C:\RekindleServer\Rekindle.Server.exe" start= auto
sc description Rekindle "Rekindle self-hosted reader server"
sc start Rekindle
```

To stop or remove it:

```cmd
sc stop Rekindle
sc delete Rekindle
```

---

## Updating

From version 1.5.0 the server can update itself from the project's releases. Stop it first, run the binary with an update flag, then start it again:

```bash
sudo systemctl stop rekindle
/opt/rekindle/Rekindle.Server --update
sudo systemctl start rekindle
```

On Windows, use `sc stop Rekindle`, `C:\RekindleServer\Rekindle.Server.exe --update`, then `sc start Rekindle`.

| Flag | What it does |
|------|--------------|
| `--check-update` | Shows the newest release and pre-release, and installs nothing |
| `--update` | Installs the newest **stable** release, if it is newer than yours |
| `--dev-update` | Installs the newest release **including pre-releases** (betas, release candidates), for testing |

The update only replaces the files that ship in the release. It never touches your `data/` and cache folders, any `appsettings.*.json`, or anything else you keep in the server's folder.

Your `appsettings.json` carries over as it is: every value you set stays. If the new release adds settings your file doesn't have yet, they are added with their defaults so you can find and change them. From 1.6.3 the server does this itself each time it starts, and logs the settings it added, so it happens however you updated: with `--update` (even from an older version), by unzipping a release, or from a package. If your file has comments or trailing commas, which a rewrite would lose, it is left exactly as it is, and if the server can't write to its folder it leaves the file and says so in the log. Either way, settings your file doesn't mention still use their defaults. Each download is checked against the SHA-256 published with the release and refused if it doesn't match. If anything fails part-way, every file is put back as it was.

An update never moves you to an older version: on a pre-release, `--update` waits until a stable release newer than yours exists.

Releases come from `https://git.jombo.uk/Jombo/rekindle`. If it can't be reached, the update falls back to the same releases on GitHub (`https://github.com/Jombolio/rekindle`) and says so. See `Rekindle.UpdateSource` and `Rekindle.UpdateFallbackSource` in [Configuration](Configuration).

---

## Next Steps

- [Configuration](Configuration) | Change the port, data path, cache size, and more
- [HTTPS](HTTPS) | Expose the server securely over the internet
- [First Connection & Setup](First-Connection-and-Setup) | Connect a client and create the first admin account
