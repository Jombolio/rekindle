using System.Collections.Concurrent;
using System.IO.Compression;
using System.Text.RegularExpressions;
using System.Xml;
using System.Xml.Linq;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace Rekindle.Core.Services;

public sealed record BookChapter(string Title, string Path);

public sealed record BookManifest(string Title, IReadOnlyList<BookChapter> Chapters);

/// One file from inside a book, streamed straight out of the archive.
public sealed record BookContent(Stream Stream, string ContentType);

/// Text books (EPUB and the Kindle formats). Clients read these as EPUB: EPUB
/// files are used as they are, and Kindle files are converted once and cached.
///
/// Reading streams one file at a time from inside the archive. Nothing is
/// extracted and nothing is held between requests, and a client that can read a
/// book is never handed the book as a file.
public partial class BookService(IOptions<RekindleOptions> options, ILogger<BookService> logger)
{
    private const long MaxOpfBytes = 16 * 1024 * 1024;
    private const int TitleScanChars = 16 * 1024;
    private const int MaxCachedManifests = 512;

    /// Larger than any real chapter or image; stops a crafted archive expanding
    /// without limit while it is being streamed.
    private const long MaxContentBytes = 256L * 1024 * 1024;

    private static readonly HashSet<string> KindleFormats =
        new(StringComparer.OrdinalIgnoreCase) { "mobi", "azw", "azw3" };

    /// What may be read from inside a book. Packaging files aren't content.
    private static readonly Dictionary<string, string> ContentTypes = new(StringComparer.OrdinalIgnoreCase)
    {
        [".html"] = "text/html",
        [".htm"] = "text/html",
        [".xhtml"] = "text/html",
        [".css"] = "text/css",
        [".png"] = "image/png",
        [".jpg"] = "image/jpeg",
        [".jpeg"] = "image/jpeg",
        [".gif"] = "image/gif",
        [".webp"] = "image/webp",
        [".bmp"] = "image/bmp",
        [".svg"] = "image/svg+xml",
    };

    private readonly string _cacheDir = Path.Combine(options.Value.CachePath, "books");
    private readonly ConcurrentDictionary<string, SemaphoreSlim> _locks = new();
    private readonly ConcurrentDictionary<(string Path, DateTime Written), BookManifest> _manifests = new();

    public static bool IsTextBook(string format) =>
        format.Equals("epub", StringComparison.OrdinalIgnoreCase) || KindleFormats.Contains(format);

    /// Path of a readable EPUB for this book.
    /// <exception cref="MobiNotSupportedException">The Kindle file can't be converted.</exception>
    public async Task<string> GetEpubPathAsync(string mediaId, string filePath)
    {
        if (!KindleFormats.Contains(Path.GetExtension(filePath).TrimStart('.')))
            return filePath;

        var cached = Path.Combine(_cacheDir, $"{mediaId}.epub");
        if (IsFresh(cached, filePath)) return cached;

        var sem = _locks.GetOrAdd(mediaId, _ => new SemaphoreSlim(1, 1));
        await sem.WaitAsync();
        try
        {
            if (IsFresh(cached, filePath)) return cached;

            Directory.CreateDirectory(_cacheDir);
            // Written beside the target and moved into place, so a request can
            // never be served a half-written book.
            var temp = $"{cached}.{Guid.NewGuid():N}.tmp";
            try
            {
                await Task.Run(() => MobiConverter.ConvertToEpub(filePath, temp));
                File.Move(temp, cached, overwrite: true);
            }
            finally
            {
                if (File.Exists(temp)) File.Delete(temp);
            }
            logger.LogInformation("Converted Kindle book to EPUB for {MediaId}", mediaId);
            return cached;
        }
        finally
        {
            sem.Release();
        }
    }

    /// The book's title and chapters, or null when it can't be read. Chapter titles
    /// come from the start of each chapter only, so this stays cheap on big books.
    public BookManifest? GetManifest(string epubPath)
    {
        var key = (epubPath, File.GetLastWriteTimeUtc(epubPath));
        if (_manifests.TryGetValue(key, out var known)) return known;

        try
        {
            using var zip = ZipFile.OpenRead(epubPath);
            var entries = IndexEntries(zip);
            var spine = ReadSpine(entries);
            if (spine is null) return null;

            var chapters = spine.Value.Paths
                .Select(path => new BookChapter(ChapterTitle(entries[path]) ?? FileName(path), entries[path].FullName))
                .ToList();
            var manifest = new BookManifest(spine.Value.Title, chapters);

            if (_manifests.Count >= MaxCachedManifests) _manifests.Clear();
            _manifests[key] = manifest;
            return manifest;
        }
        catch (Exception e) when (IsBadBook(e))
        {
            logger.LogWarning(e, "Could not read {Path}", epubPath);
            return null;
        }
    }

    /// Opens one file inside the book for streaming, or returns null if there's no
    /// such file or it isn't reading content. The caller disposes the stream, which
    /// also closes the archive.
    public BookContent? OpenContent(string epubPath, string path)
    {
        if (!ContentTypes.TryGetValue(Path.GetExtension(path), out var contentType)) return null;

        ZipArchive? zip = null;
        try
        {
            zip = ZipFile.OpenRead(epubPath);
            if (!IndexEntries(zip).TryGetValue(NormalizePath(path), out var entry))
            {
                zip.Dispose();
                return null;
            }
            return new BookContent(new BookContentStream(entry.Open(), zip), contentType);
        }
        catch (Exception e) when (IsBadBook(e))
        {
            zip?.Dispose();
            logger.LogWarning(e, "Could not read {Entry} from {Path}", path, epubPath);
            return null;
        }
    }

    /// Readable chapters in an EPUB: the spine entries that exist in the file.
    /// Matches how the clients count them, so progress lines up. Returns 0 when
    /// the book can't be read.
    public int CountChapters(string epubPath)
    {
        try
        {
            using var zip = ZipFile.OpenRead(epubPath);
            return ReadSpine(IndexEntries(zip))?.Paths.Count ?? 0;
        }
        catch (Exception e) when (IsBadBook(e))
        {
            logger.LogWarning(e, "Could not read chapters from {Path}", epubPath);
            return 0;
        }
    }

    private static bool IsBadBook(Exception e) =>
        e is InvalidDataException or IOException or XmlException or UnauthorizedAccessException;

    private static Dictionary<string, ZipArchiveEntry> IndexEntries(ZipArchive zip)
    {
        var entries = new Dictionary<string, ZipArchiveEntry>(StringComparer.OrdinalIgnoreCase);
        foreach (var entry in zip.Entries) entries[NormalizePath(entry.FullName)] = entry;
        return entries;
    }

    private static (string Title, List<string> Paths)? ReadSpine(Dictionary<string, ZipArchiveEntry> entries)
    {
        var container = ReadXml(entries, "META-INF/container.xml");
        var opfPath = container?.Descendants().FirstOrDefault(e => e.Name.LocalName == "rootfile")
            ?.Attribute("full-path")?.Value;
        if (opfPath is null) return null;

        var opf = ReadXml(entries, NormalizePath(opfPath));
        if (opf is null) return null;

        var opfDir = opfPath.Contains('/') ? opfPath[..(opfPath.LastIndexOf('/') + 1)] : string.Empty;
        var manifest = opf.Descendants().Where(e => e.Name.LocalName == "item")
            .Select(e => (Id: e.Attribute("id")?.Value, Href: e.Attribute("href")?.Value))
            .Where(i => i.Id is not null && i.Href is not null)
            .GroupBy(i => i.Id!)
            .ToDictionary(g => g.Key, g => g.First().Href!);

        var paths = new List<string>();
        foreach (var itemRef in opf.Descendants().Where(e => e.Name.LocalName == "itemref"))
        {
            if (itemRef.Attribute("idref")?.Value is not { } id || !manifest.TryGetValue(id, out var href)) continue;
            var path = NormalizePath(opfDir + Uri.UnescapeDataString(href.Split('#')[0]));
            if (entries.ContainsKey(path)) paths.Add(path);
        }

        var title = opf.Descendants().FirstOrDefault(e => e.Name.LocalName == "title")?.Value.Trim();
        return (string.IsNullOrEmpty(title) ? "Unknown" : title, paths);
    }

    /// The first heading, else the title, looking only at the start of the chapter.
    /// Many books repeat the book's name in every title, so a heading is better.
    private static string? ChapterTitle(ZipArchiveEntry entry)
    {
        using var reader = new StreamReader(entry.Open());
        var buffer = new char[TitleScanChars];
        var text = new string(buffer, 0, reader.ReadBlock(buffer, 0, buffer.Length));

        var match = HeadingOrTitle().Match(text);
        if (!match.Success) return null;
        var heading = TagPattern().Replace(match.Groups[1].Value + match.Groups[2].Value, string.Empty);
        var clean = System.Net.WebUtility.HtmlDecode(heading).Trim();
        return clean.Length == 0 ? null : clean;
    }

    private static string FileName(string path) => path[(path.LastIndexOf('/') + 1)..];

    private static bool IsFresh(string cached, string source) =>
        File.Exists(cached) && File.GetLastWriteTimeUtc(cached) >= File.GetLastWriteTimeUtc(source);

    private static XDocument? ReadXml(Dictionary<string, ZipArchiveEntry> entries, string path)
    {
        if (!entries.TryGetValue(path, out var entry) || entry.Length > MaxOpfBytes) return null;
        using var stream = entry.Open();
        // Books are untrusted input: ignore DTDs and never resolve external entities.
        using var reader = XmlReader.Create(stream, new XmlReaderSettings
        {
            DtdProcessing = DtdProcessing.Ignore,
            XmlResolver = null,
        });
        return XDocument.Load(reader);
    }

    private static string NormalizePath(string path)
    {
        var parts = new List<string>();
        foreach (var segment in path.Replace('\\', '/').Split('/'))
        {
            if (segment is "" or ".") continue;
            if (segment == "..")
            {
                if (parts.Count > 0) parts.RemoveAt(parts.Count - 1);
            }
            else parts.Add(segment);
        }
        return string.Join('/', parts);
    }

    // A heading wins over <title>, but <title> comes first in a document, so
    // this prefers a heading anywhere in the scanned text.
    [GeneratedRegex(@"<h[1-3]\b[^>]*>(.*?)</h[1-3]\s*>|\A(?!.*<h[1-3]\b).*?<title[^>]*>(.*?)</title>", RegexOptions.IgnoreCase | RegexOptions.Singleline)]
    private static partial Regex HeadingOrTitle();
    [GeneratedRegex(@"<[^>]+>")]
    private static partial Regex TagPattern();

    /// A file being streamed out of a book: keeps its archive open until it's
    /// finished with, and stops at the size limit.
    private sealed class BookContentStream(Stream inner, ZipArchive zip) : Stream
    {
        private long _total;

        public override bool CanRead => true;
        public override bool CanSeek => false;
        public override bool CanWrite => false;
        public override long Length => throw new NotSupportedException();
        public override long Position
        {
            get => throw new NotSupportedException();
            set => throw new NotSupportedException();
        }

        public override int Read(byte[] buffer, int offset, int count) =>
            Count(inner.Read(buffer, offset, count));

        public override async ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken cancellationToken = default) =>
            Count(await inner.ReadAsync(buffer, cancellationToken));

        private int Count(int read)
        {
            _total += read;
            if (_total > MaxContentBytes)
                throw new InvalidDataException("Book content exceeds the size limit (possible decompression bomb).");
            return read;
        }

        public override void Flush() { }
        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
        public override void SetLength(long value) => throw new NotSupportedException();
        public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                inner.Dispose();
                zip.Dispose();
            }
            base.Dispose(disposing);
        }
    }
}
