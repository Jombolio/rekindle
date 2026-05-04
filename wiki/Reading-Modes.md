# Reading Modes

The Rekindle reader has four settings that control how pages are displayed and navigated. All four are toggled from the top bar while an archive is open, and all are remembered per-archive.

---

## Paged mode (default)

Pages are shown one at a time (or as a spread in double-page mode). Navigate by:

- **Tapping / clicking** the left or right third of the screen
- **Arrow keys** (`←` / `→`) or `A` / `D` on desktop
- **Swiping** on touch screens

When you reach the last page, the next action advances to the following archive in the series. When you reach the first page, the previous action goes back to the previous archive.

---

## Scroll mode

All pages are laid out as a single continuous vertical list. Useful for webtoon-style content where panels flow top to bottom.

Navigate by:

- **Scrolling** with the mouse wheel or touchscreen
- **Arrow Down / Page Down** to scroll forward by ~90% of the viewport height
- **Arrow Up / Page Up** to scroll backward

Reaching the top or bottom of the scroll view advances to the adjacent archive.

---

## Double-page mode

Portrait pages are paired side-by-side into a spread. The cover (page 0) always occupies its own slide to match the physical book convention.

**Automatic spread detection:** The server checks each page's dimensions when the archive is first extracted. Any page wider than it is tall (landscape orientation) is treated as a full-width spread and shown alone on its own slide, never paired with another page.

**Spine gap:** An adjustable gap between the two pages in a spread. Use the `−` and `+` controls in the top bar to change it in 4-pixel steps (0–64 px). The default is seamless (0 px), with the inner edges of both pages meeting at the centre.

**Zoom in double-page mode:** Pinch or scroll to zoom. The entire spread zooms from its centre point, so both pages scale and pan together as a single unit.

---

## Reading direction (RTL / LTR)

Controls the direction of page turns.

| Setting | Behaviour |
|---------|-----------|
| **LTR** (left-to-right) | Right tap / swipe / arrow advances; left goes back. Default for Comics and Books. |
| **RTL** (right-to-left) | Left tap / swipe / arrow advances; right goes back. Default for Manga. |

The default is set automatically based on the library type when you open an archive for the first time. If you explicitly toggle direction, that choice is remembered for that specific archive and takes priority over the library default.

---

## How settings are remembered

| Setting | Remembered per-archive | Session inheritance |
|---------|------------------------|---------------------|
| Reading direction | Yes, if explicitly toggled | No, stays at library default for new archives |
| Double-page | Yes, if explicitly toggled | Yes, carries to the next archive in the session |
| Scroll mode | Yes, if explicitly toggled | Yes, carries to the next archive in the session |

Session inheritance means switching to double-page for one archive automatically applies it to the next chapter you open, without having to toggle it again. An explicit per-archive setting always takes priority.

---

## Covers

Covers are generated automatically when a library is scanned. The server resizes the cover image to fit within 300×450 pixels and caches it as a JPEG. Cover generation runs in the background after a scan.

### Custom covers

You can override the auto-generated cover by providing a file named `rekindle-cover` or `cover` (any supported image extension: `.jpg`, `.jpeg`, `.png`, `.webp`, `.gif`, `.bmp`).

**For a series folder**, place the file directly inside the series folder, next to the archive files:

```
/media/comics/Batman by Scott Snyder/
    rekindle-cover.jpg        ← used as the series thumbnail
    Batman Vol 1.cbz
    Batman Vol 2.cbz
```

**Inside an archive**, include a file named `rekindle-cover.*` or `cover.*` as an entry inside the CBZ/CBR. It will be used instead of the first page regardless of sort order.

Priority is: `rekindle-cover.*` → `cover.*` → first image in the archive (fallback).

To apply a new custom cover, delete the cached cover for that series (via **Admin → Cache → Clear**) and trigger a library scan, or simply clear the full page cache.
