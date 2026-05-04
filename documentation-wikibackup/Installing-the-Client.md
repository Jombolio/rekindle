# Installing the Client

---

## Linux

### 1. Download

Grab the latest `RekindleClient-linux-x64.zip` from the [Releases page](https://github.com/Jombolio/rekindle/releases).

### 2. Extract

```bash
unzip RekindleClient-linux-x64.zip -d RekindleClient
cd RekindleClient
```

### 3. Make the binary executable

```bash
chmod +x rekindle
```

### 4. Run

```bash
./rekindle
```

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
