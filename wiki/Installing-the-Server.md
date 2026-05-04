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

## Next Steps

- [Configuration](Configuration) | Change the port, data path, cache size, and more
- [HTTPS](HTTPS) | Expose the server securely over the internet
- [First Connection & Setup](First-Connection-and-Setup) | Connect a client and create the first admin account
