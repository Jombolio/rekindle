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

## Text books

Books (EPUB, MOBI, AZW and AZW3) have their own reader, set up from the **Aa** button in its top bar or from **Settings → Books**. Both change the same settings, which apply to every book and take effect straight away.

### Layout

| Layout | What it does |
|--------|--------------|
| **Scroll by chapter** | One chapter at a time, scrolled. The arrows move between chapters. The default. |
| **Continuous scroll** | The whole book as one scroll: the next chapter follows the last, and earlier ones load above as you scroll back. |
| **Single page** | A page at a time. Pages break between lines, never through one. |
| **Two pages** | A spread of two pages side by side, for wide screens and landscape. |

In the page layouts, turn pages by tapping or clicking near either side of the page, with the arrow keys, Page Up/Down or Space, with the mouse wheel, by swiping (Android), or with the arrows in the bottom bar. Turning past a chapter's last page opens the next chapter, and turning back from its first opens the previous chapter's last page. The bottom bar shows the page within the chapter.

Your place is kept as a chapter and a position within it, so switching layout, or reading on another device in another layout, opens where you left off.

### Fonts

Besides the system's serif, sans-serif and monospace fonts, three readability fonts come with the apps, free under the SIL Open Font License (their licences are under **Licences** in Settings):

- **OpenDyslexic**, with weighted letter bottoms, designed for readers with dyslexia.
- **Atkinson Hyperlegible**, from the Braille Institute, with letters that are hard to mistake for one another, for low vision.
- **Lexend**, with wider letters and spacing, designed to make reading more fluent.

### Readability and accessibility

- **Spacing:** line, letter, word and paragraph spacing. Paragraph spacing at zero keeps the book's own.
- **Line width:** how long lines get before wrapping, about 50 to 120 characters.
- **Alignment:** the book's own, left-aligned or justified. Text a book deliberately centres, such as title pages, stays centred.
- **Theme:** Match app, Light, Dark, Sepia, and two high-contrast themes: white on black and black on white. The palette button in a book changes it for that visit only.
- **Bold text:** sets all text in bold.
- **Page-turn animation:** turn it off for pages that change at once.
- **Reading ruler:** a band that keeps your eye on the lines you're reading, with the rest of the page dimmed. On desktop it follows the pointer; on Android it stays put while the text moves under it, and the handle at its right edge moves it.

---

## Dictionary

Text books have a built-in English dictionary that works offline.

- **Desktop:** select a word and its meaning appears beside it. Double-clicking is the quickest way to select one. Click anywhere or press Esc to close it. You can turn this off in **Settings → Books**.
- **Android:** long-press a word, then tap **Define**. Tap the page to close it.

The pop-up floats over the page, so your place doesn't move. It's English only, and PDFs and comics don't have selectable text.

Definitions come from [WordNet](https://wordnet.princeton.edu/), © Princeton University. See `desktop/assets/dictionary/LICENSE-WordNet.txt`.

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
