# First Connection & Setup

This page covers connecting the Rekindle client to your server for the first time and getting your first library set up.

---

## 1. Find your server address

Your server address is the IP address (or hostname) of the machine running Rekindle, plus the port (default `8080`).

**Examples:**
- Local network: `http://192.168.1.10:8080`
- Domain with HTTPS: `https://rekindle.yourdomain.com`

If you are running the client on the same machine as the server, you can use `http://localhost:8080`.

---

## 2. Add the server in the client

1. Open the Rekindle client.
2. Tap or click **Add Server**.
3. Enter the server URL and tap **Connect**.

---

## 3. First-time admin setup

On first launch, the server prints a one-time **setup token** to its console output:

```
════════════════════════════════════════════════════════
  REKINDLE FIRST-TIME SETUP
  No admin account exists. Use the token below to
  complete setup via the client.
  Setup token: abc123...
  This token is one-time and invalidated after use.
════════════════════════════════════════════════════════
```

The client will detect that no admin account exists and prompt you for this token. Enter it, then choose a username and password for your admin account.

> If you missed the token, restart the server, it will print a new one as long as no admin account exists.

---

## 4. Create a library

1. Log in as admin.
2. Open the **Admin Panel** (gear icon or menu).
3. Go to the **Libraries** tab.
4. Tap **Add Library**.
5. Enter a name, the **path on the server machine** where your archives live (e.g. `/mnt/media/comics`), and the library type (Comics, Manga, or Books).
6. Tap **Save**.

---

## 5. Scan the library

After creating the library, tap **Scan** next to it. The server will index all supported archive files in that folder and generate cover thumbnails.

Large libraries may take a minute or two to scan. The scan runs in the background, you can start browsing as soon as the first items appear.

---

## 6. Start reading

Navigate to your new library from the main screen and tap any series or archive to start reading.

---

## Adding more users

Go to **Admin Panel → Users** to create additional accounts. Each user gets their own reading progress. See [User Permissions](User-Permissions) for a breakdown of permission levels.
