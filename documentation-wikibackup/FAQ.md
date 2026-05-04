# FAQ

---

## Installation

### Where do I download Rekindle?

- **Server and desktop clients (Linux/Windows):** [GitHub Releases](https://github.com/Jombolio/rekindle/releases)
- **Android:** F-Droid, via the custom repository at `https://fdroid.jombo.uk/repo`, see [Installing the Client](Installing-the-Client) for step-by-step instructions.

---

### The server won't start on Linux

Make sure the binary is executable:

```bash
chmod +x Rekindle.Server
./Rekindle.Server
```

If it still fails then check that .NET 10 runtime is installed:

```bash
dotnet --version
```

---

### Windows says "Windows protected your PC" when I run the client

The binaries are not signed. Click **More info → Run anyway** to proceed. It's a scam perpetuated by big tech to make sure you don't download free anti-viruses (/j)

---

### I can't install the Android APK

You need to allow installation from unknown sources. The exact path varies by device, but is usually: **Settings → Apps → Special app access → Install unknown apps**, then select your file manager or browser and enable it.

If you installed via F-Droid you should not see this prompt, F-Droid should handle it automatically.

---

## Setup

### I missed the setup token. How do I get a new one?

Stop the server and restart it. As long as no admin account exists in the database, it will print a new setup token each time it starts. Just try not to forget the password for the administrator account.

---

### I forgot my admin password

Stop the server. Open the SQLite database at `data/rekindle.db` with any SQLite tool (e.g. [DB Browser for SQLite](https://sqlitebrowser.org)). In the `users` table, you can update the password hash, or delete the row entirely to recreate the account on next setup. Then restart.

If that's too hard/too complex, just delete the whole database if you're feeling ballsy.

---

### The client can't connect to the server

Check the following:

1. The server is running and shows no errors in its console output.
2. You are using the correct IP address and port (default `8080`).
3. The server is reachable from the client's network (try `curl http://SERVER_IP:8080` or open it in a browser).
4. If connecting from outside your local network, ensure the port is forwarded and (ideally) HTTPS is configured, see [HTTPS](HTTPS).
5. If running a firewall on the server machine, allow inbound connections on port 8080 (or whichever port you configured).
6. If running on a rented dedicated server or VPS, check the web-panel to ensure their web-based firewall is also configured.

---

## Libraries & Scanning

### My archives aren't showing up after a scan

- Make sure the file extensions are in the [supported list](Supported-Formats) (`.cbz`, `.cbr`, `.epub`, `.mobi`, `.pdf`).
- The library's root path must point to the **parent** folder containing your series subfolders, not to a specific series folder.
- Check the server console output for scan errors.

---

### The scan finished but covers aren't loading

Cover generation runs as a background job after the scan. Give it a minute, then refresh the library view.

---

### How do I update a library after adding new files?

Go to **Admin Panel → Libraries** and tap **Scan** next to the library. Only new and changed files are processed, it is safe to scan at any time.

---

## Reading

### My reading progress isn't syncing

Progress is synced to the server when you close an archive or after a few seconds of inactivity. If the device is offline, progress is saved locally and synced automatically the next time a connection is available.

---

### I finished an archive but it keeps opening on the last page

This should not happen from version 0.9 onwards, completed archives reopen at page 1. If you are on an older version, update the client from the beta to the release at least.

---

### What does each permission level mean?

See [User Permissions](User-Permissions).

---

## Metadata

### Metadata scraping returned "No results found"

The search uses the series folder name. Try renaming the folder to match the series title exactly as it appears on ComicVine or MyAnimeList (without volume numbers, publisher names, or edition tags), then re-scrape.

---

### Comics aren't showing an About card

The About card only appears for **Comics** and **Manga** library types. Make sure the library was created with the correct type, and that a ComicVine API key is configured under **Admin Panel → APIs**.

---

### Can I edit metadata manually?

Yes! Users with permission level 3 (Contributor) or higher can tap the pencil icon in the About card to edit any metadata field directly.

---

## Server

### How do I change the port?

Edit `appsettings.json` and set `"Urls": "http://0.0.0.0:YOUR_PORT"`, then restart. See [Configuration](Configuration).

---

### How do I move the data folder to another drive?

Set `Rekindle.DataPath` and `Rekindle.CachePath` in `appsettings.json` to paths on the new drive, copy the existing `data/` folder there, then restart. See [Configuration](Configuration).

---

### How do I update the server?

1. Stop the running server.
2. Replace the binary (and native libraries) with the new version from the release archive.
3. Leave the `data/` folder in place, they are not overwritten by the updates, make sure to update `appsettings.json` though.
4. Start the new binary. Database migrations run automatically on startup.

---

### Does Rekindle work on a NAS or home server?

Yes, any machine that can run .NET 10 works. The server is designed to run unattended and uses minimal resources at idle.
