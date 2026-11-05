using System.Collections.Concurrent;
using System.IO.Compression;
using System.Xml;
using System.Xml.Linq;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace Rekindle.Core.Services;

/// Text books (EPUB, MOBI). Clients read these as EPUB: EPUB files are served
/// as they are, and MOBI files are converted once and cached.
public class BookService(IOptions<RekindleOptions> options, ILogger<BookService> logger)
{
    private const long MaxOpfBytes = 16 * 1024 * 1024;

    private readonly string _cacheDir = Path.Combine(options.Value.CachePath, "books");
    private readonly ConcurrentDictionary<string, SemaphoreSlim> _locks = new();

    public static bool IsTextBook(string format) =>
        format.Equals("epub", StringComparison.OrdinalIgnoreCase)
        || format.Equals("mobi", StringComparison.OrdinalIgnoreCase);

    /// Path of a readable EPUB for this book.
    /// <exception cref="MobiNotSupportedException">The MOBI can't be converted.</exception>
    public async Task<string> GetEpubPathAsync(string mediaId, string filePath)
    {
        if (!Path.GetExtension(filePath).Equals(".mobi", StringComparison.OrdinalIgnoreCase))
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
            logger.LogInformation("Converted MOBI to EPUB for {MediaId}", mediaId);
            return cached;
        }
        finally
        {
            sem.Release();
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
            var entries = new Dictionary<string, ZipArchiveEntry>(StringComparer.OrdinalIgnoreCase);
            foreach (var entry in zip.Entries) entries[entry.FullName] = entry;

            var container = ReadXml(entries, "META-INF/container.xml");
            var opfPath = container?.Descendants().FirstOrDefault(e => e.Name.LocalName == "rootfile")
                ?.Attribute("full-path")?.Value;
            if (opfPath is null) return 0;

            var opf = ReadXml(entries, opfPath);
            if (opf is null) return 0;

            var opfDir = opfPath.Contains('/') ? opfPath[..(opfPath.LastIndexOf('/') + 1)] : string.Empty;
            var manifest = opf.Descendants().Where(e => e.Name.LocalName == "item")
                .Select(e => (Id: e.Attribute("id")?.Value, Href: e.Attribute("href")?.Value))
                .Where(i => i.Id is not null && i.Href is not null)
                .GroupBy(i => i.Id!)
                .ToDictionary(g => g.Key, g => g.First().Href!);

            return opf.Descendants().Where(e => e.Name.LocalName == "itemref")
                .Count(r => r.Attribute("idref")?.Value is { } id
                            && manifest.TryGetValue(id, out var href)
                            && entries.ContainsKey(NormalizePath(opfDir + Uri.UnescapeDataString(href.Split('#')[0]))));
        }
        catch (Exception e) when (e is InvalidDataException or IOException or XmlException or UnauthorizedAccessException)
        {
            logger.LogWarning(e, "Could not read chapters from {Path}", epubPath);
            return 0;
        }
    }

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
        foreach (var segment in path.Split('/'))
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
}
