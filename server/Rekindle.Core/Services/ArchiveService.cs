using System.Collections.Concurrent;
using System.Text.Json;
using Docnet.Core;
using Docnet.Core.Models;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Rekindle.Core.Utilities;
using SharpCompress.Archives;
using SharpCompress.Common;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.PixelFormats;
using SixLabors.ImageSharp.Processing;

namespace Rekindle.Core.Services;

public class ArchiveService(IOptions<RekindleOptions> options, ILogger<ArchiveService> logger)
{
    private static readonly HashSet<string> ImageExtensions =
        [".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp"];

    private static readonly HashSet<string> ArchiveExtensions =
        LibraryScannerService.SupportedExtensions;

    private readonly string _pagesCache = Path.Combine(options.Value.CachePath, "pages");
    private readonly long _maxCacheBytes = options.Value.CacheMaxSizeBytes;

    private readonly ConcurrentDictionary<string, SemaphoreSlim> _extractLocks = new();
    private readonly ConcurrentDictionary<string, DateTime> _accessTimes = new();

    public async Task<string?> GetPagePathAsync(string mediaId, string filePath, int pageNum)
    {
        await EnsureExtractedAsync(mediaId, filePath);

        var manifest = await LoadManifestAsync(mediaId);
        if (manifest is null || pageNum < 0 || pageNum >= manifest.Pages.Count)
            return null;

        _accessTimes[mediaId] = DateTime.UtcNow;

        return Path.Combine(_pagesCache, mediaId, manifest.Pages[pageNum]);
    }

    public async Task<int> GetPageCountAsync(string mediaId, string filePath)
    {
        await EnsureExtractedAsync(mediaId, filePath);
        var manifest = await LoadManifestAsync(mediaId);
        return manifest?.Pages.Count ?? 0;
    }

    public async Task<Stream?> OpenCoverStreamAsync(string filePath)
    {
        // For folder entries, use the first archive inside the directory
        if (Directory.Exists(filePath))
        {
            var first = Directory
                .EnumerateFiles(filePath, "*.*", SearchOption.AllDirectories)
                .Where(f => ArchiveExtensions.Contains(Path.GetExtension(f).ToLowerInvariant()))
                .OrderBy(f => f, NaturalStringComparer.Instance)
                .FirstOrDefault();

            if (first is null)
                return null;

            filePath = first;
        }
        else if (!File.Exists(filePath))
        {
            return null;
        }

        try
        {
            return Path.GetExtension(filePath).ToLowerInvariant() == ".pdf"
                ? await RenderPdfCoverAsync(filePath)
                : await ExtractArchiveCoverAsync(filePath);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Failed to open cover stream for {FilePath}", filePath);
            return null;
        }
    }

    private static async Task<Stream?> ExtractArchiveCoverAsync(string filePath)
    {
        using var archive = ArchiveFactory.Open(filePath);
        var candidates = archive.Entries
            .Where(e => !e.IsDirectory && IsImageEntry(e.Key))
            .OrderBy(e => e.Key, NaturalStringComparer.Instance)
            .ToList();

        foreach (var entry in candidates)
        {
            var ms = new MemoryStream();
            using (var entryStream = entry.OpenEntryStream())
                await entryStream.CopyToAsync(ms);
            ms.Position = 0;

            // Skip entries that have an image extension but aren't actually
            // decodable (e.g. macOS .__MACOSX artifacts, corrupt entries).
            try
            {
                await Image.IdentifyAsync(ms);
                ms.Position = 0;
                return ms;
            }
            catch (UnknownImageFormatException)
            {
                await ms.DisposeAsync();
            }
        }

        return null;
    }

    private static Task<Stream?> RenderPdfCoverAsync(string filePath)
    {
        using var doc = DocLib.Instance.GetDocReader(filePath, new PageDimensions(1080, 1440));
        using var page = doc.GetPageReader(0);

        var width = page.GetPageWidth();
        var height = page.GetPageHeight();
        var rawBytes = page.GetImage(); // BGRA 8-bit per channel

        using var image = Image.LoadPixelData<Bgra32>(rawBytes, width, height);

        var ms = new MemoryStream();
        image.SaveAsJpeg(ms);
        ms.Position = 0;
        return Task.FromResult<Stream?>(ms);
    }

    // ── Extraction ──────────────────────────────────────────────────────────

    private async Task EnsureExtractedAsync(string mediaId, string filePath)
    {
        var outDir = Path.Combine(_pagesCache, mediaId);
        var manifestPath = Path.Combine(outDir, "manifest.json");

        if (File.Exists(manifestPath))
        {
            _accessTimes[mediaId] = DateTime.UtcNow;
            return;
        }

        var sem = _extractLocks.GetOrAdd(mediaId, _ => new SemaphoreSlim(1, 1));
        await sem.WaitAsync();
        try
        {
            if (File.Exists(manifestPath))
                return;

            if (!Directory.Exists(filePath) && !File.Exists(filePath))
            {
                logger.LogWarning("Media file not found, skipping extraction: {FilePath}", filePath);
                return;
            }

            if (Directory.Exists(filePath))
                await ExtractFolderAsync(mediaId, filePath, outDir, manifestPath);
            else if (Path.GetExtension(filePath).Equals(".pdf", StringComparison.OrdinalIgnoreCase))
                await ExtractPdfAsync(mediaId, filePath, outDir, manifestPath);
            else
                await ExtractArchiveAsync(mediaId, filePath, outDir, manifestPath);

            await EvictCacheIfNeededAsync();
        }
        finally
        {
            sem.Release();
        }
    }

    /// Extracts a single archive file (CBZ/CBR/etc.) into <paramref name="outDir"/>.
    private async Task ExtractArchiveAsync(string mediaId, string filePath, string outDir, string manifestPath)
    {
        Directory.CreateDirectory(outDir);
        logger.LogInformation("Extracting {FilePath}...", filePath);

        try
        {
            var (pages, spreads) = await ExtractSingleArchiveToDir(filePath, outDir, prefix: "");

            await WriteManifestAsync(mediaId, manifestPath, pages, spreads);
            logger.LogInformation("Extracted {Count} pages for {MediaId}", pages.Count, mediaId);
        }
        catch
        {
            if (Directory.Exists(outDir))
                Directory.Delete(outDir, recursive: true);
            throw;
        }
    }

    /// Renders all pages of a PDF to JPEG images in <paramref name="outDir"/>.
    private async Task ExtractPdfAsync(string mediaId, string filePath, string outDir, string manifestPath)
    {
        Directory.CreateDirectory(outDir);
        logger.LogInformation("Extracting PDF {FilePath}...", filePath);

        try
        {
            var pages = new List<string>();
            var spreads = new List<bool>();

            using var doc = DocLib.Instance.GetDocReader(filePath, new PageDimensions(1080, 1440));
            var pageCount = doc.GetPageCount();

            for (var i = 0; i < pageCount; i++)
            {
                using var pageReader = doc.GetPageReader(i);
                var width = pageReader.GetPageWidth();
                var height = pageReader.GetPageHeight();
                var rawBytes = pageReader.GetImage(); // BGRA 8-bit per channel

                using var image = Image.LoadPixelData<Bgra32>(rawBytes, width, height);
                var pageName = $"{i:D5}.jpg";
                await using var fileStream = File.Create(Path.Combine(outDir, pageName));
                await image.SaveAsJpegAsync(fileStream);
                pages.Add(pageName);
                spreads.Add(width > height);
            }

            await WriteManifestAsync(mediaId, manifestPath, pages, spreads);
            logger.LogInformation("Extracted {Count} pages for {MediaId}", pages.Count, mediaId);
        }
        catch
        {
            if (Directory.Exists(outDir))
                Directory.Delete(outDir, recursive: true);
            throw;
        }
    }

    /// Extracts a folder of chapter archives, producing a flat page list across all chapters.
    private async Task ExtractFolderAsync(string mediaId, string folderPath, string outDir, string manifestPath)
    {
        Directory.CreateDirectory(outDir);
        logger.LogInformation("Extracting folder {FolderPath}...", folderPath);

        try
        {
            var chapterFiles = Directory
                .EnumerateFiles(folderPath, "*.*", SearchOption.AllDirectories)
                .Where(f => ArchiveExtensions.Contains(Path.GetExtension(f).ToLowerInvariant()))
                .OrderBy(f => f, NaturalStringComparer.Instance)
                .ToList();

            var allPages = new List<string>();
            var allSpreads = new List<bool>();

            for (var ci = 0; ci < chapterFiles.Count; ci++)
            {
                var chapterSubDir = Path.Combine(outDir, $"ch_{ci:D5}");
                Directory.CreateDirectory(chapterSubDir);

                // Pages are stored as "ch_00000/00000.jpg" relative to outDir
                var (chapterPages, chapterSpreads) = await ExtractSingleArchiveToDir(
                    chapterFiles[ci], chapterSubDir, prefix: $"ch_{ci:D5}/");

                allPages.AddRange(chapterPages);
                allSpreads.AddRange(chapterSpreads);
            }

            await WriteManifestAsync(mediaId, manifestPath, allPages, allSpreads);
            logger.LogInformation(
                "Extracted {Count} pages across {Chapters} chapters for {MediaId}",
                allPages.Count, chapterFiles.Count, mediaId);
        }
        catch
        {
            if (Directory.Exists(outDir))
                Directory.Delete(outDir, recursive: true);
            throw;
        }
    }

    /// Extracts image entries from a single archive into <paramref name="targetDir"/>.
    /// Returns page paths (prefixed with <paramref name="prefix"/>) and a spread flag per page.
    private async Task<(List<string> Pages, List<bool> Spreads)> ExtractSingleArchiveToDir(
        string archivePath, string targetDir, string prefix)
    {
        using var archive = ArchiveFactory.Open(archivePath);
        var imageEntries = archive.Entries
            .Where(e => !e.IsDirectory && IsImageEntry(e.Key))
            .OrderBy(e => e.Key, NaturalStringComparer.Instance)
            .ToList();

        var pages = new List<string>(imageEntries.Count);
        var spreads = new List<bool>(imageEntries.Count);

        for (var i = 0; i < imageEntries.Count; i++)
        {
            var entry = imageEntries[i];
            var ext = Path.GetExtension(entry.Key ?? ".jpg").ToLowerInvariant();
            var pageName = $"{i:D5}{ext}";
            var fullPath = Path.Combine(targetDir, pageName);

            // Write the entry to disk first, fully closing the stream so the
            // file is flushed before ImageSharp reads the header below.
            using (var entryStream = entry.OpenEntryStream())
            await using (var fileStream = File.Create(fullPath))
            {
                await entryStream.CopyToAsync(fileStream);
            }

            // Detect spread: landscape images are double-page spreads.
            // Image.IdentifyAsync only reads the header — no full decode needed.
            try
            {
                var info = await Image.IdentifyAsync(fullPath);
                spreads.Add(info.Width > info.Height);
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Could not identify image dimensions for page {Index} in {Archive}", i, archivePath);
                spreads.Add(false);
            }

            pages.Add($"{prefix}{pageName}");
        }

        return (pages, spreads);
    }

    private async Task WriteManifestAsync(string mediaId, string manifestPath, List<string> pages, List<bool> spreads)
    {
        var manifest = new PageManifest
        {
            MediaId = mediaId,
            Pages = pages,
            Spreads = spreads,
            ExtractedAt = DateTime.UtcNow,
            Version = ManifestVersion,
        };
        await File.WriteAllTextAsync(manifestPath, JsonSerializer.Serialize(manifest));
        _accessTimes[mediaId] = DateTime.UtcNow;
    }

    public async Task<IReadOnlyList<bool>> GetSpreadsAsync(string mediaId, string filePath)
    {
        await EnsureExtractedAsync(mediaId, filePath);
        var manifest = await LoadManifestAsync(mediaId);
        if (manifest is null) return [];

        // Re-detect spreads when: (a) the list length doesn't match (pre-spread
        // detection manifests), or (b) the version is older than ManifestVersion
        // (e.g. the extraction logic was fixed and old results can't be trusted).
        if (manifest.Spreads.Count != manifest.Pages.Count || manifest.Version < ManifestVersion)
        {
            var baseDir = Path.Combine(_pagesCache, mediaId);
            var spreads = new List<bool>(manifest.Pages.Count);
            foreach (var page in manifest.Pages)
            {
                try
                {
                    var info = await Image.IdentifyAsync(Path.Combine(baseDir, page));
                    spreads.Add(info.Width > info.Height);
                }
                catch
                {
                    spreads.Add(false);
                }
            }
            manifest.Spreads = spreads;
            manifest.Version = ManifestVersion;

            var manifestPath = Path.Combine(_pagesCache, mediaId, "manifest.json");
            await File.WriteAllTextAsync(manifestPath, JsonSerializer.Serialize(manifest));
        }

        return manifest.Spreads;
    }

    private async Task<PageManifest?> LoadManifestAsync(string mediaId)
    {
        var manifestPath = Path.Combine(_pagesCache, mediaId, "manifest.json");
        if (!File.Exists(manifestPath))
            return null;

        var json = await File.ReadAllTextAsync(manifestPath);
        return JsonSerializer.Deserialize<PageManifest>(json);
    }

    // ── Cache eviction ──────────────────────────────────────────────────────

    private async Task EvictCacheIfNeededAsync()
    {
        var cacheDir = new DirectoryInfo(_pagesCache);
        if (!cacheDir.Exists)
            return;

        var totalSize = cacheDir.EnumerateFiles("*", SearchOption.AllDirectories).Sum(f => f.Length);
        if (totalSize <= _maxCacheBytes)
            return;

        var byAccess = _accessTimes
            .OrderBy(kv => kv.Value)
            .Select(kv => kv.Key)
            .ToList();

        foreach (var id in byAccess)
        {
            if (totalSize <= _maxCacheBytes * 0.8)
                break;

            var dir = new DirectoryInfo(Path.Combine(_pagesCache, id));
            if (!dir.Exists)
                continue;

            var dirSize = dir.EnumerateFiles("*", SearchOption.AllDirectories).Sum(f => f.Length);
            dir.Delete(recursive: true);
            _accessTimes.TryRemove(id, out _);
            totalSize -= dirSize;

            logger.LogInformation("Evicted cached pages for {MediaId} ({Size} bytes freed)", id, dirSize);
        }

        await Task.CompletedTask;
    }

    private static bool IsImageEntry(string? key) =>
        key is not null && ImageExtensions.Contains(Path.GetExtension(key).ToLowerInvariant());

    // Increment this when the extraction logic changes in a way that requires
    // old cached manifests to be re-processed (e.g. spread detection fix).
    private const int ManifestVersion = 2;

    private sealed class PageManifest
    {
        public string MediaId { get; set; } = string.Empty;
        public List<string> Pages { get; set; } = [];
        public List<bool> Spreads { get; set; } = [];
        public DateTime ExtractedAt { get; set; }
        public int Version { get; set; } = 0;
    }
}
