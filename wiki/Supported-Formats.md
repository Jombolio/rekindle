# Supported Formats

| Format | Extension | Notes |
|--------|-----------|-------|
| Comic Book ZIP | `.cbz` | Most common comic format |
| Comic Book RAR | `.cbr` | RAR-archived comics |
| EPUB | `.epub` | Rendered natively — no WebView |
| MOBI | `.mobi` | |
| PDF | `.pdf` | Native renderer, no external dependency |

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
