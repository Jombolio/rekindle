# Installing the Client

---

## Linux

Two options. The AppImage is recommended unless you have a reason to prefer the
portable zip.

### Option 1 | AppImage (recommended)

One self-contained file. Nothing to install, nothing to extract.

**1. Download**

Grab the latest `RekindleClient-linux-x86_64.AppImage` from the [Releases page](https://github.com/Jombolio/rekindle/releases).

**2. Make it executable**

```bash
chmod +x RekindleClient-linux-x86_64.AppImage
```

Most file managers can do this instead, via **Properties → Permissions → Allow
executing file as program**.

**3. Run**

Double-click it, or:

```bash
./RekindleClient-linux-x86_64.AppImage
```

Keep it wherever you like — Downloads, `~/Applications`, a USB stick. Moving or
renaming it later is fine. To update, replace the file with a newer one.

**Adding it to your application menu** is optional. If you install
[AppImageLauncher](https://github.com/TheAssassin/AppImageLauncher), it will
offer to do this the first time you run any AppImage and will handle the icon
and menu entry for you. Otherwise just run the file directly.

> **If it refuses to start** on a locked-down system without FUSE (some
> containers and minimal installs), run it with
> `./RekindleClient-linux-x86_64.AppImage --appimage-extract-and-run`.

### Option 2 | Portable zip

The plain application folder, if you would rather manage it yourself.

**1. Download**

Grab the latest `RekindleClient-linux-x64.zip` from the [Releases page](https://github.com/Jombolio/rekindle/releases).

**2. Extract**

```bash
unzip RekindleClient-linux-x64.zip -d RekindleClient
cd RekindleClient
```

**3. Make the binary executable**

```bash
chmod +x rekindle
```

**4. Run**

```bash
./rekindle
```

<details>
<summary><b>Optional:</b> add a menu entry for the portable zip</summary>

Run this from inside the extracted folder:

```bash
ID=io.github.Jombolio.Rekindle
mkdir -p ~/.local/share/applications ~/.local/share/icons/hicolor/256x256/apps
cp data/icon.png ~/.local/share/icons/hicolor/256x256/apps/$ID.png
cat > ~/.local/share/applications/$ID.desktop <<EOF
[Desktop Entry]
Name=Rekindle
Comment=Self-hosted comic, manga, and book reader
Exec="$PWD/rekindle"
Icon=$ID
Type=Application
Categories=Graphics;Viewer;
StartupWMClass=$ID
EOF
```

The entry points at the folder's current location, so you will need to run this
again if you ever move it. The AppImage has no such limitation.

</details>

---

## Windows

### 1. Download

Grab the latest `RekindleClient-windows-x64.zip` from the [Releases page](https://github.com/Jombolio/rekindle/releases).

### 2. Extract

Right-click the zip → **Extract All**. Place the folder wherever you like.

### 3. Run

Double-click `rekindle.exe`.

> **SmartScreen warning:** Because the binary is not code-signed, Windows may show a "Windows protected your PC" prompt on first launch. Click **More info → Run anyway** to proceed.

---

## Android

The Android client is distributed through a custom F-Droid repository.

### What is F-Droid?

[F-Droid](https://f-droid.org) is a free, open-source app store for Android. Unlike the Play Store it lets you add third-party repositories, which is how Rekindle is distributed.

### Step 1 | Install F-Droid

If you don't have F-Droid installed, download it from [f-droid.org](https://f-droid.org). Install the APK after allowing installation from unknown sources when prompted.

### Step 2 | Add the Rekindle repository

1. Open **F-Droid**.
2. Tap the **Settings** icon (bottom-right).
3. Tap **Repositories**.
4. Tap the **+** button (top-right).
5. Enter the repository address:
   ```
   https://fdroid.jombo.uk/repo
   ```
6. Tap **OK** (or **Add**).
7. F-Droid will fetch the repository index. This may take a few seconds.

### Step 3 | Install Rekindle

1. Return to the F-Droid main screen.
2. Pull down to refresh if the app does not appear immediately.
3. Search for **Rekindle**.
4. Tap **Install**.

### Staying up to date

F-Droid checks for updates automatically. When a new Rekindle release is published to the repository, F-Droid will notify you and let you update through the normal update flow.

---

## Next Steps

- [First Connection & Setup](First-Connection-and-Setup) — connect to your server for the first time
