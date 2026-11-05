using System.IO.Compression;
using System.Net;
using System.Text;
using System.Text.RegularExpressions;

namespace Rekindle.Core.Services;

/// Thrown for MOBI files that can't be converted: DRM-protected or corrupt. The
/// message is safe to show to the user.
public sealed class MobiNotSupportedException(string message) : Exception(message);

/// Converts MOBI files to EPUB so the clients only need one book reader. Handles
/// classic MOBI text, including the copy embedded in dual MOBI/KF8 files, and
/// KF8-only files (see MobiConverter.Kf8.cs).
public static partial class MobiConverter
{
    private const int MaxTextBytes = 256 * 1024 * 1024;
    private const int MaxHuffmanDepth = 32;
    private const string Damaged = "This MOBI file is damaged.";

    public static void ConvertToEpub(string mobiPath, string epubPath)
    {
        var bytes = File.ReadAllBytes(mobiPath);
        using var output = File.Create(epubPath);
        try
        {
            var book = MobiBook.Parse(bytes);
            if (book.IsKf8) WriteKf8Epub(book, output);
            else WriteEpub(book, output);
        }
        // Lengths and offsets in these files can't be trusted: running off the
        // end of something is what a damaged or hostile file looks like.
        catch (Exception e) when (e is IndexOutOfRangeException or ArgumentException
                                      or OverflowException or KeyNotFoundException or FormatException)
        {
            throw new MobiNotSupportedException(Damaged);
        }
    }

    /// The embedded cover image, or null when the file has none or can't be read.
    public static byte[]? ReadCover(string mobiPath)
    {
        try
        {
            return MobiBook.Parse(File.ReadAllBytes(mobiPath), withText: false).CoverImage;
        }
        catch (MobiNotSupportedException)
        {
            return null;
        }
    }

    // ── Parsing ─────────────────────────────────────────────────────────────

    private sealed class MobiBook
    {
        public bool IsKf8;
        public string Title = "Unknown";
        public string? Author;
        public Encoding TextEncoding = Encoding.Latin1;
        public string RawText = string.Empty; // One char per source byte (Latin-1).
        public int FirstImageRecord;
        public byte[]? CoverImage;
        public byte[][] Records = [];

        public byte[]? ImageForRecIndex(int recIndex)
        {
            var record = (long)FirstImageRecord + recIndex - 1;
            if (recIndex < 1 || record < 0 || record >= Records.Length) return null;
            return ImageExtension(Records[record]) is null ? null : Records[record];
        }

        public static MobiBook Parse(byte[] file, bool withText = true)
        {
            if (file.Length < 78 || Encoding.ASCII.GetString(file, 60, 8) != "BOOKMOBI")
                throw new MobiNotSupportedException("This file is not a valid MOBI book.");

            var records = ReadRecords(file);
            if (records.Length == 0 || records[0].Length < 132)
                throw new MobiNotSupportedException(Damaged);
            var header = records[0];

            if (U16(header, 12) != 0)
                throw new MobiNotSupportedException("This MOBI file is protected by DRM and can't be opened.");
            if (Encoding.ASCII.GetString(header, 16, 4) != "MOBI")
                throw new MobiNotSupportedException(Damaged);

            var headerLength = (int)Math.Min(U32(header, 20), int.MaxValue / 2);

            var book = new MobiBook
            {
                IsKf8 = U32(header, 36) >= 8,
                Records = records,
                TextEncoding = U32(header, 28) == 65001 ? Encoding.UTF8 : Windows1252.Instance,
                FirstImageRecord = (int)Math.Min(U32(header, 108), int.MaxValue),
            };

            var nameOffset = U32(header, 84);
            var nameLength = U32(header, 88);
            if (nameLength > 0 && (ulong)nameOffset + nameLength <= (ulong)header.Length)
                book.Title = book.TextEncoding.GetString(header, (int)nameOffset, (int)nameLength);

            if ((U32(header, 128) & 0x40) != 0)
                book.ReadExth(header, 16 + headerLength);

            if (withText)
            {
                var extraFlags = headerLength >= 0xE4 && header.Length >= 244 ? U16(header, 242) : 0;
                book.RawText = Encoding.Latin1.GetString(DecompressText(records, header, extraFlags));
            }
            return book;
        }

        private void ReadExth(byte[] header, int offset)
        {
            if (offset + 12 > header.Length || Encoding.ASCII.GetString(header, offset, 4) != "EXTH")
                return;

            var count = U32(header, offset + 8);
            var pos = offset + 12;
            for (uint i = 0; i < count && pos + 8 <= header.Length; i++)
            {
                var type = U32(header, pos);
                var length = U32(header, pos + 4);
                if (length < 8 || pos + (long)length > header.Length) return;
                var dataLength = (int)length - 8;

                if (type == 100)
                    Author = TextEncoding.GetString(header, pos + 8, dataLength);
                else if (type == 503)
                    Title = TextEncoding.GetString(header, pos + 8, dataLength);
                else if (type == 201 && dataLength >= 4 && U32(header, pos + 8) < int.MaxValue)
                    CoverImage = ImageForRecIndex((int)U32(header, pos + 8) + 1);

                pos += (int)length;
            }
        }
    }

    private static byte[][] ReadRecords(byte[] file)
    {
        var count = U16(file, 76);
        if (78 + count * 8L > file.Length) throw new MobiNotSupportedException(Damaged);

        var records = new byte[count][];
        for (var i = 0; i < count; i++)
        {
            var start = U32(file, 78 + i * 8);
            var end = i + 1 < count ? U32(file, 78 + (i + 1) * 8) : (uint)file.Length;
            if (start > end || end > file.Length) throw new MobiNotSupportedException(Damaged);
            records[i] = file.AsSpan((int)start, (int)(end - start)).ToArray();
        }
        return records;
    }

    private static byte[] DecompressText(byte[][] records, byte[] header, int extraFlags)
    {
        var compression = U16(header, 0);
        var recordCount = U16(header, 8);
        if (recordCount >= records.Length) throw new MobiNotSupportedException(Damaged);
        if (compression is not (1 or 2 or 17480))
            throw new MobiNotSupportedException("This MOBI file uses an unsupported compression method.");

        var huffman = compression == 17480 ? HuffCdic.Load(records, header) : null;

        using var text = new MemoryStream();
        for (var i = 1; i <= recordCount; i++)
        {
            var data = records[i].AsSpan(0, TextLengthWithoutTrailers(records[i], extraFlags));
            if (compression == 1) text.Write(data);
            else if (compression == 2) DecompressPalmDoc(data, text);
            else huffman!.Decompress(data.ToArray(), text, 0);

            if (text.Length > MaxTextBytes)
                throw new MobiNotSupportedException("This MOBI book is too large to open.");
        }
        return text.ToArray();
    }

    /// Records can end with trailing data that isn't part of the text. Which
    /// entries are present is given by the header's extra data flags.
    private static int TextLengthWithoutTrailers(byte[] record, int flags)
    {
        var length = record.Length;
        for (var bits = flags >> 1; bits != 0; bits >>= 1)
        {
            if ((bits & 1) == 0) continue;
            var size = 0;
            var shift = 0;
            for (var pos = length - 1; pos >= 0 && shift < 28; pos--)
            {
                var value = record[pos];
                size |= (value & 0x7F) << shift;
                shift += 7;
                if ((value & 0x80) != 0) break;
            }
            length = Math.Max(0, length - size);
        }
        if ((flags & 1) != 0 && length > 0)
            length = Math.Max(0, length - ((record[length - 1] & 3) + 1));
        return length;
    }

    internal static void DecompressPalmDoc(ReadOnlySpan<byte> src, MemoryStream dst)
    {
        var start = dst.Length;
        for (var i = 0; i < src.Length;)
        {
            var c = src[i++];
            if (c is >= 1 and <= 8)
            {
                var n = Math.Min((int)c, src.Length - i);
                dst.Write(src.Slice(i, n));
                i += n;
            }
            else if (c < 0x80)
            {
                dst.WriteByte(c);
            }
            else if (c >= 0xC0)
            {
                dst.WriteByte((byte)' ');
                dst.WriteByte((byte)(c ^ 0x80));
            }
            else
            {
                if (i >= src.Length) break;
                var pair = (c << 8) | src[i++];
                var distance = (pair >> 3) & 0x7FF;
                var length = (pair & 7) + 3;
                if (distance == 0 || distance > dst.Length - start) continue;
                // Byte by byte: a copy may overlap the bytes it is producing.
                for (var k = 0; k < length; k++)
                    dst.WriteByte(dst.GetBuffer()[dst.Length - distance]);
            }
        }
    }

    /// Mobipocket's Huffman + dictionary compression, used by "high compression" books.
    internal sealed class HuffCdic
    {
        private readonly (int CodeLength, bool Terminal, ulong MaxCode)[] _table1 = new (int, bool, ulong)[256];
        private readonly ulong[] _minCode = new ulong[33];
        private readonly ulong[] _maxCode = new ulong[33];
        private readonly List<(byte[]? Data, bool Expanded)> _dictionary = [];

        public static HuffCdic Load(byte[][] records, byte[] header)
        {
            var first = U32(header, 112);
            var count = U32(header, 116);
            if (count < 2 || (ulong)first + count > (ulong)records.Length)
                throw new MobiNotSupportedException(Damaged);
            return Load(records.Skip((int)first).Take((int)count).ToArray());
        }

        internal static HuffCdic Load(byte[][] huffAndCdic)
        {
            var result = new HuffCdic();
            try
            {
                result.ReadHuff(huffAndCdic[0]);
                foreach (var cdic in huffAndCdic.Skip(1)) result.ReadCdic(cdic);
            }
            catch (Exception e) when (e is ArgumentException or IndexOutOfRangeException)
            {
                throw new MobiNotSupportedException(Damaged);
            }
            return result;
        }

        private void ReadHuff(byte[] huff)
        {
            if (Encoding.ASCII.GetString(huff, 0, 4) != "HUFF") throw new MobiNotSupportedException(Damaged);
            var offset1 = (int)U32(huff, 8);
            var offset2 = (int)U32(huff, 12);

            for (var i = 0; i < 256; i++)
            {
                var v = U32(huff, offset1 + i * 4);
                var codeLength = (int)(v & 0x1F);
                if (codeLength == 0) throw new MobiNotSupportedException(Damaged);
                var maxCode = (((ulong)(v >> 8) + 1) << (32 - codeLength)) - 1;
                _table1[i] = (codeLength, (v & 0x80) != 0, maxCode);
            }
            for (var length = 1; length <= 32; length++)
            {
                var min = U32(huff, offset2 + (length - 1) * 8);
                var max = U32(huff, offset2 + (length - 1) * 8 + 4);
                _minCode[length] = (ulong)min << (32 - length);
                _maxCode[length] = (((ulong)max + 1) << (32 - length)) - 1;
            }
        }

        private void ReadCdic(byte[] cdic)
        {
            if (Encoding.ASCII.GetString(cdic, 0, 4) != "CDIC") throw new MobiNotSupportedException(Damaged);
            var phrases = (long)U32(cdic, 8);
            var bits = (int)U32(cdic, 12);
            var n = (int)Math.Min(1L << Math.Min(bits, 30), phrases - _dictionary.Count);
            for (var i = 0; i < n; i++)
            {
                var offset = U16(cdic, 16 + i * 2);
                var header = U16(cdic, 16 + offset);
                _dictionary.Add((cdic.AsSpan(18 + offset, header & 0x7FFF).ToArray(), (header & 0x8000) != 0));
            }
        }

        public void Decompress(byte[] data, MemoryStream output, int depth)
        {
            if (depth > MaxHuffmanDepth) throw new MobiNotSupportedException(Damaged);

            var bitsLeft = data.Length * 8L;
            var padded = new byte[data.Length + 12];
            data.CopyTo(padded, 0);
            var pos = 0;
            var x = U64(padded, 0);
            var n = 32;

            while (true)
            {
                if (n <= 0)
                {
                    pos += 4;
                    x = U64(padded, pos);
                    n += 32;
                }
                var code = (x >> n) & 0xFFFFFFFF;
                var (codeLength, terminal, maxCode) = _table1[code >> 24];
                if (!terminal)
                {
                    while (codeLength < 32 && code < _minCode[codeLength]) codeLength++;
                    maxCode = _maxCode[codeLength];
                }
                n -= codeLength;
                bitsLeft -= codeLength;
                if (bitsLeft < 0) return;

                var index = (maxCode - code) >> (32 - codeLength);
                if (index >= (ulong)_dictionary.Count) throw new MobiNotSupportedException(Damaged);

                var (phrase, expanded) = _dictionary[(int)index];
                if (phrase is null) throw new MobiNotSupportedException(Damaged);
                if (!expanded)
                {
                    // Marked null while expanding so a self-referencing phrase is
                    // reported as damage instead of recursing forever.
                    _dictionary[(int)index] = (null, false);
                    using var inner = new MemoryStream();
                    Decompress(phrase, inner, depth + 1);
                    phrase = inner.ToArray();
                    _dictionary[(int)index] = (phrase, true);
                }
                output.Write(phrase);
                if (output.Length > MaxTextBytes)
                    throw new MobiNotSupportedException("This MOBI book is too large to open.");
            }
        }
    }

    // ── Markup → EPUB ───────────────────────────────────────────────────────

    /// [FullDocument]: Body is already a complete HTML document (KF8), rather than
    /// the inside of a body element that still needs wrapping.
    private sealed record Chapter(string FileName, string Title, string Body, bool FullDocument = false);

    private static void WriteEpub(MobiBook book, Stream output)
    {
        var withAnchors = InsertFilePosAnchors(book.RawText);
        var pieces = PageBreak().Split(StripDocumentShell(withAnchors))
            .Where(HasContent)
            .ToList();
        if (pieces.Count == 0) throw new MobiNotSupportedException("This MOBI file has no readable text.");

        // Which output file each anchor ends up in, so links can point at it.
        var anchorFile = new Dictionary<string, string>();
        for (var i = 0; i < pieces.Count; i++)
            foreach (Match m in AnchorId().Matches(pieces[i]))
                anchorFile[m.Groups[1].Value] = ChapterFile(i);

        var images = new SortedDictionary<int, (string Name, byte[] Data)>();
        var chapters = new List<Chapter>();
        for (var i = 0; i < pieces.Count; i++)
        {
            var html = FilePosLink().Replace(pieces[i], m =>
            {
                var id = "fp" + m.Groups[1].Value;
                return anchorFile.TryGetValue(id, out var file) ? $"href=\"{file}#{id}\"" : string.Empty;
            });
            html = RecIndex().Replace(html, m =>
            {
                if (!int.TryParse(m.Groups[1].Value, out var index)) return string.Empty;
                var data = book.ImageForRecIndex(index);
                if (data is null) return string.Empty;
                var name = $"images/{index:D5}{ImageExtension(data)}";
                images[index] = (name, data);
                return $"src=\"{name}\"";
            });
            // Everything so far has been byte-accurate Latin-1; now it can be
            // decoded as what it really is.
            var decoded = book.TextEncoding.GetString(Encoding.Latin1.GetBytes(html));
            chapters.Add(new Chapter(ChapterFile(i), ChapterTitle(decoded, i), decoded));
        }

        var coverName = book.CoverImage is { } cover ? $"images/cover{ImageExtension(cover)}" : null;
        var resources = images.Values.Select(v => (v.Name, v.Data)).ToList();
        if (coverName is not null) resources.Add((coverName, book.CoverImage!));
        WritePackage(book, chapters, resources, coverName, output);
    }

    private static void WritePackage(
        MobiBook book, List<Chapter> chapters, List<(string Name, byte[] Data)> resources, string? coverName, Stream output)
    {
        using var zip = new ZipArchive(output, ZipArchiveMode.Create, leaveOpen: true);
        // The EPUB format requires "mimetype" first and uncompressed.
        WriteEntry(zip, "mimetype", "application/epub+zip", CompressionLevel.NoCompression);
        WriteEntry(zip, "META-INF/container.xml",
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
              <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
            </container>
            """);
        WriteEntry(zip, "OEBPS/content.opf", BuildOpf(book, chapters, resources.Select(r => r.Name).Where(n => n != coverName), coverName));
        WriteEntry(zip, "OEBPS/toc.ncx", BuildNcx(book, chapters));

        foreach (var chapter in chapters)
        {
            WriteEntry(zip, $"OEBPS/{chapter.FileName}", chapter.FullDocument ? chapter.Body :
                $"""
                <html xmlns="http://www.w3.org/1999/xhtml"><head><meta charset="utf-8"/><title>{Xml(chapter.Title)}</title></head>
                <body>{chapter.Body}</body></html>
                """);
        }
        foreach (var (name, data) in resources) WriteEntry(zip, $"OEBPS/{name}", data);
    }

    private static string ChapterFile(int index) => $"part{index:D4}.html";

    /// Link targets are byte offsets into the text. Adds an anchor at each one,
    /// moving it in front of the tag when an offset lands inside a tag.
    internal static string InsertFilePosAnchors(string text)
    {
        var targets = FilePosLink().Matches(text)
            .Select(m => int.TryParse(m.Groups[1].Value, out var v) ? v : -1)
            .Where(v => v >= 0 && v <= text.Length)
            .Distinct()
            .OrderByDescending(v => v);

        var result = new StringBuilder(text);
        foreach (var target in targets)
        {
            var at = target;
            if (at > 0)
            {
                var open = text.LastIndexOf('<', at - 1);
                var close = text.LastIndexOf('>', at - 1);
                if (open > close) at = open;
            }
            result.Insert(at, $"<a id=\"fp{target}\"></a>");
        }
        return result.ToString();
    }

    private static string StripDocumentShell(string text)
    {
        // Links can target offsets before <body>; keep any anchors placed in the
        // head so those links still resolve once the head is removed.
        var head = HeadSection().Match(text);
        var headAnchors = head.Success
            ? string.Concat(AnchorTag().Matches(head.Value).Select(m => m.Value))
            : string.Empty;
        var body = head.Success ? text.Remove(head.Index, head.Length) : text;
        return headAnchors + ShellTag().Replace(body, string.Empty);
    }

    private static bool HasContent(string html) =>
        html.Contains("recindex", StringComparison.OrdinalIgnoreCase)
        || !string.IsNullOrWhiteSpace(WebUtility.HtmlDecode(AnyTag().Replace(html, string.Empty)));

    private static string ChapterTitle(string html, int index)
    {
        var heading = Heading().Match(html);
        if (heading.Success)
        {
            var text = WebUtility.HtmlDecode(AnyTag().Replace(heading.Groups[1].Value, string.Empty)).Trim();
            if (text.Length > 0) return text;
        }
        return $"Part {index + 1}";
    }

    private static string BuildOpf(MobiBook book, List<Chapter> chapters, IEnumerable<string> images, string? cover)
    {
        var sb = new StringBuilder();
        sb.Append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>");
        sb.Append("<package xmlns=\"http://www.idpf.org/2007/opf\" version=\"2.0\" unique-identifier=\"id\">");
        sb.Append("<metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\">");
        sb.Append($"<dc:identifier id=\"id\">urn:rekindle:{Guid.NewGuid()}</dc:identifier>");
        sb.Append($"<dc:title>{Xml(book.Title)}</dc:title><dc:language>und</dc:language>");
        if (book.Author is not null) sb.Append($"<dc:creator>{Xml(book.Author)}</dc:creator>");
        if (cover is not null) sb.Append("<meta name=\"cover\" content=\"cover-image\"/>");
        sb.Append("</metadata><manifest><item id=\"ncx\" href=\"toc.ncx\" media-type=\"application/x-dtbncx+xml\"/>");
        for (var i = 0; i < chapters.Count; i++)
            sb.Append($"<item id=\"c{i}\" href=\"{chapters[i].FileName}\" media-type=\"application/xhtml+xml\"/>");
        var n = 0;
        foreach (var image in images)
            sb.Append($"<item id=\"i{n++}\" href=\"{image}\" media-type=\"{MimeFor(image)}\"/>");
        if (cover is not null)
            sb.Append($"<item id=\"cover-image\" href=\"{cover}\" media-type=\"{MimeFor(cover)}\"/>");
        sb.Append("</manifest><spine toc=\"ncx\">");
        for (var i = 0; i < chapters.Count; i++) sb.Append($"<itemref idref=\"c{i}\"/>");
        sb.Append("</spine></package>");
        return sb.ToString();
    }

    private static string BuildNcx(MobiBook book, List<Chapter> chapters)
    {
        var sb = new StringBuilder();
        sb.Append("<?xml version=\"1.0\" encoding=\"UTF-8\"?><ncx xmlns=\"http://www.daisy.org/z3986/2005/ncx/\" version=\"2005-1\"><head/>");
        sb.Append($"<docTitle><text>{Xml(book.Title)}</text></docTitle><navMap>");
        for (var i = 0; i < chapters.Count; i++)
            sb.Append($"<navPoint id=\"n{i}\" playOrder=\"{i + 1}\"><navLabel><text>{Xml(chapters[i].Title)}</text></navLabel><content src=\"{chapters[i].FileName}\"/></navPoint>");
        sb.Append("</navMap></ncx>");
        return sb.ToString();
    }

    private static void WriteEntry(ZipArchive zip, string name, string text, CompressionLevel level = CompressionLevel.Optimal) =>
        WriteEntry(zip, name, new UTF8Encoding(false).GetBytes(text), level);

    private static void WriteEntry(ZipArchive zip, string name, byte[] data, CompressionLevel level = CompressionLevel.Optimal)
    {
        using var stream = zip.CreateEntry(name, level).Open();
        stream.Write(data);
    }

    private static string Xml(string value) => WebUtility.HtmlEncode(value);

    private static string MimeFor(string name) => Path.GetExtension(name) switch
    {
        ".png" => "image/png",
        ".gif" => "image/gif",
        ".bmp" => "image/bmp",
        ".svg" => "image/svg+xml",
        ".css" => "text/css",
        _ => "image/jpeg",
    };

    private static string? ImageExtension(byte[] d)
    {
        if (d.Length >= 3 && d[0] == 0xFF && d[1] == 0xD8 && d[2] == 0xFF) return ".jpg";
        if (d.Length >= 4 && d[0] == 0x89 && d[1] == 0x50 && d[2] == 0x4E && d[3] == 0x47) return ".png";
        if (d.Length >= 3 && d[0] == 0x47 && d[1] == 0x49 && d[2] == 0x46) return ".gif";
        if (d.Length >= 2 && d[0] == 0x42 && d[1] == 0x4D) return ".bmp";
        return null;
    }

    private static int U16(byte[] d, int o) => (d[o] << 8) | d[o + 1];
    private static uint U32(byte[] d, int o) => ((uint)d[o] << 24) | ((uint)d[o + 1] << 16) | ((uint)d[o + 2] << 8) | d[o + 3];
    private static ulong U64(byte[] d, int o) => ((ulong)U32(d, o) << 32) | U32(d, o + 4);

    /// .NET only ships code page 1252 with an extra provider package; this is the
    /// table's one difference from Latin-1, the 0x80–0x9F punctuation block.
    private sealed class Windows1252 : Encoding
    {
        public static readonly Windows1252 Instance = new();

        private const string High =
            "€\u0081‚ƒ„…†‡ˆ‰Š‹Œ\u008DŽ\u008F" +
            "\u0090‘’“”•–—˜™š›œ\u009DžŸ";

        public override int GetCharCount(byte[] bytes, int index, int count) => count;
        public override int GetChars(byte[] bytes, int byteIndex, int byteCount, char[] chars, int charIndex)
        {
            for (var i = 0; i < byteCount; i++)
            {
                var b = bytes[byteIndex + i];
                chars[charIndex + i] = b is >= 0x80 and <= 0x9F ? High[b - 0x80] : (char)b;
            }
            return byteCount;
        }

        // Only ever used for decoding.
        public override int GetByteCount(char[] chars, int index, int count) => throw new NotSupportedException();
        public override int GetBytes(char[] chars, int charIndex, int charCount, byte[] bytes, int byteIndex) => throw new NotSupportedException();
        public override int GetMaxByteCount(int charCount) => charCount;
        public override int GetMaxCharCount(int byteCount) => byteCount;
    }

    [GeneratedRegex(@"<mbp:pagebreak\s*/?>(?:\s*</mbp:pagebreak>)?", RegexOptions.IgnoreCase)]
    private static partial Regex PageBreak();
    [GeneratedRegex(@"filepos\s*=\s*[""']?0*(\d+)[""']?", RegexOptions.IgnoreCase)]
    private static partial Regex FilePosLink();
    [GeneratedRegex(@"recindex\s*=\s*[""']?0*(\d+)[""']?", RegexOptions.IgnoreCase)]
    private static partial Regex RecIndex();
    [GeneratedRegex(@"<a id=""(fp\d+)""></a>")]
    private static partial Regex AnchorId();
    [GeneratedRegex(@"<a id=""fp\d+""></a>")]
    private static partial Regex AnchorTag();
    [GeneratedRegex(@"<head\b.*?</head\s*>", RegexOptions.IgnoreCase | RegexOptions.Singleline)]
    private static partial Regex HeadSection();
    [GeneratedRegex(@"</?(?:html|body)\b[^>]*>", RegexOptions.IgnoreCase)]
    private static partial Regex ShellTag();
    [GeneratedRegex(@"<[^>]*>")]
    private static partial Regex AnyTag();
    [GeneratedRegex(@"<h[1-3]\b[^>]*>(.*?)</h[1-3]\s*>", RegexOptions.IgnoreCase | RegexOptions.Singleline)]
    private static partial Regex Heading();
}
