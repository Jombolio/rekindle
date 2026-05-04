# Metadata APIs

Rekindle can automatically fetch series information; synopsis, genres, score, publication year, and status from third-party databases. This appears as an "About" card at the top of any manga or comic series view.

Metadata is stored in the server's local database after the first scrape. It is never silently overwritten; if a re-scrape returns different data, a diff dialog lets you choose which version to keep.

Only **admins** can trigger scrapes or configure API keys. All users can view cached metadata.

---

## Sources

| Source | Used for | Key required? | Rate limit |
|--------|----------|---------------|------------|
| [ComicVine](https://comicvine.gamespot.com) | Comics only | Yes | 200 req / resource / hour |
| [MyAnimeList](https://myanimelist.net) | Manga only | Yes | Varies |
| [AniList](https://anilist.co) | Manga only (automatic fallback) | No | 30 req / min |

Routing is **strict and exclusive**:

- **Comic libraries** → ComicVine only. MAL and AniList are never queried. No key = no metadata.
- **Manga libraries** → MyAnimeList first (if a key is set), then AniList as a fallback if MAL returns no result.
- The sources are never mixed across library types.

---

## Getting a ComicVine API Key

ComicVine is a community-maintained comic database covering Western comics, graphic novels, and more.

1. Create a free account at [comicvine.gamespot.com](https://comicvine.gamespot.com).
2. Go to **[comicvine.gamespot.com/api](https://comicvine.gamespot.com/api)**.
3. Your API key is shown at the top of the page under **"Your API Key"**. Copy it.
4. In the Rekindle client, go to **Admin Panel → APIs** and paste it into **ComicVine API Key**, then click **Save**.

> ComicVine uses velocity detection in addition to the hourly quota. Rekindle enforces a minimum 1-second gap between requests to avoid triggering it.

---

## Getting a MyAnimeList Client ID

MyAnimeList is the primary source for manga metadata.

1. Log in at [myanimelist.net](https://myanimelist.net) (create a free account if you don't have one).
2. Go to **[myanimelist.net/apiconfig](https://myanimelist.net/apiconfig)** and click **Create ID**.
3. Fill in the form:
   - **App Name:** `Rekindle` (or any name)
   - **App Type:** `other`
   - **App Description:** A brief note (e.g. "Personal self-hosted reader")
   - **App Redirect URL:** `http://localhost` (required as a placeholder even though Rekindle does not use OAuth)
4. Accept the licence agreement and click **Submit**.
5. Copy the **Client ID** shown on the next page.
6. In the Rekindle client, go to **Admin Panel → APIs** and paste it into **MAL Client ID**, then click **Save**.

> Rekindle only makes read-only `GET` requests to MAL. It never posts to or modifies your account.

---

## AniList

AniList is used automatically as a fallback when MAL is not configured or returns no result. No registration or API key is required. Rekindle enforces a sliding-window cap of 30 requests per minute to stay within AniList's rate limits.

---

## Scraping metadata for a series

1. Navigate to any manga or comic **series** (the folder view showing the list of issues, not an individual issue).
2. An **About** card appears at the top of the issue list.
3. As an admin, tap the **↻ (refresh)** icon in the About card.
4. Rekindle queries the appropriate source and compares the result with any stored data:

| Result | What happens |
|--------|-------------|
| No prior metadata | Data is written immediately and displayed. |
| Matches stored data | No write is performed. A "Metadata is already up to date" notice is shown. |
| Conflicts with stored data | A **diff dialog** shows the changed fields side-by-side. Choose **Keep existing** to leave stored data unchanged, or **Use new data** to overwrite with the fresh result. |

---

## Tips

- **Folder names matter.** Rekindle searches for metadata using the series folder name. If a folder is named `One Piece (Color)`, the `(Color)` part is automatically stripped before querying. Brackets are preserved, `[Oshi No Ko]` is searched as-is.
- **No result?** Rename the folder to match the series title exactly as it appears on ComicVine or MyAnimeList, then re-scrape.
- **Manual editing** is available to users with permission level 3 or higher, tap the pencil icon in the About card to edit any field directly without triggering a rescrape.
