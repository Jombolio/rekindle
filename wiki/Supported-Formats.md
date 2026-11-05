# Supported Formats

| Format | Extension | Notes |
|--------|-----------|-------|
| Comic Book ZIP | `.cbz` | Most common comic format |
| Comic Book RAR | `.cbr` | RAR-archived comics |
| EPUB | `.epub` | Streams a chapter at a time, or reads offline once downloaded, with images and the book's own layout |
| Kindle | `.mobi` `.azw` `.azw3` | Converted to EPUB by the server when first opened, including KF8 files. DRM-protected files can't be opened or imported |
| PDF | `.pdf` | Native renderer, no external dependency |

KFX (`.kfx`) and Topaz files aren't supported.

---

## Importing Kindle Books

The desktop client can import a whole folder of books at once, from a Kindle connected over USB or any folder on your computer. This needs an account at permission level 3 or above.

Open **Upload Archive** in the library screen, then choose **Import books from a Kindle or folder**.

1. **Source.** Pick a target library, then a folder. A connected Kindle is offered automatically when it shows up as a drive, using its `documents` folder. Kindles that connect as a media device (MTP) don't show up as a drive, so copy their books to a folder first. Rekindle only reads from the source and never changes it.
2. **Preview.** Rekindle looks through the folder and its subfolders for `.mobi`, `.azw`, `.azw3`, `.kfx` and `.epub` files, skipping the `.sdr` folders Kindles keep alongside books. Each book is listed with its title, author, target library and status.
3. **Import.** Confirm to upload the ready books one at a time. You can cancel at any point, and books already uploaded are kept. The library is scanned once at the end.
4. **Report.** Every book is listed as imported, skipped or failed, with the reason.

| Status | Meaning |
|--------|---------|
| Ready | Will be uploaded |
| Already in library | The library has a file with this name, or a book with this title. To add it anyway, upload it on its own |
| DRM-protected | The book is protected by DRM, so it can't be imported |
| Unsupported format | The book is in KFX or Topaz format, which Rekindle can't read, so it can't be imported |
| Can't be read | The file is damaged, or isn't really a book |

Rekindle doesn't remove or bypass DRM, and it doesn't connect to Amazon. Books are checked before upload, so protected files stay on your device. Only the first 256 KB of a Kindle file is sent for the check.

---

## Library Types

Libraries are assigned a type when created. The type controls the default reading direction and which metadata source is queried.

| Type | Default reading direction | Metadata source |
|------|--------------------------|-----------------|
| Comics | Left-to-right | ComicVine |
| Manga | Right-to-left | MyAnimeList → AniList |
| Books | Left-to-right | — |

Reading direction can be toggled at any time inside the reader and is remembered per archive.

---

## Archive Structure

Rekindle treats a folder of archives as a **series** and the individual archive files inside as **issues or chapters**.

**Recommended layout:**

```
/media/comics/
    Batman by Scott Snyder/
        Batman Vol 1 - The Court of Owls.cbz
        Batman Vol 2 - The City of Owls.cbz
        Batman Vol 3 - Death of the Family.cbz
    Invincible/
        Invincible #001.cbz
        Invincible #002.cbz
        ...
```

Each top-level folder becomes a series card in the library. The archives inside it become the issue/chapter list when you open the series.

Nesting is supported, subfolders appear as sub-series within a series view.
