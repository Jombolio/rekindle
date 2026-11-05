using System.Text;
using System.Text.RegularExpressions;

namespace Rekindle.Core.Services;

/// KF8, the newer Kindle layout. A book's markup is split into skeletons (the
/// outline of each file) and fragments (the content cut out of them), with index
/// records saying where each fragment goes back in. Stylesheets and other text
/// live in further "flows", and everything refers to everything else through
/// kindle: URLs that have to be rewritten into ordinary links.
public static partial class MobiConverter
{
    private const uint NullIndex = 0xFFFFFFFF;

    /// One row of an index record: its name, and its numbered lists of values.
    private sealed record IndexEntry(string Name, Dictionary<int, List<long>> Tags);

    private sealed record Fragment(long InsertAt, int File);

    private static void WriteKf8Epub(MobiBook book, Stream output)
    {
        var header = book.Records[0];
        if (header.Length < 0x100) throw new MobiNotSupportedException(Damaged);

        var flows = ReadFlows(book.Records, U32(header, 0xC0), book.RawText);
        var skeletons = ReadIndex(book.Records, U32(header, 0xFC));
        var fragmentEntries = ReadIndex(book.Records, U32(header, 0xF8));

        var (parts, skeletonStarts, fragments) = AssembleParts(flows[0], skeletons, fragmentEntries);

        var resources = new SortedDictionary<string, byte[]>(StringComparer.Ordinal);
        var chapters = new List<Chapter>(parts.Count);
        for (var i = 0; i < parts.Count; i++)
        {
            var html = RewriteKindleUrls(parts[i], "", book, flows, resources, parts, skeletonStarts, fragments);
            var decoded = Encoding.UTF8.GetString(Encoding.Latin1.GetBytes(html));
            chapters.Add(new Chapter(ChapterFile(i), ChapterTitle(decoded, i), decoded, FullDocument: true));
        }

        var coverName = book.CoverImage is { } cover ? $"images/cover{ImageExtension(cover)}" : null;
        if (coverName is not null) resources[coverName] = book.CoverImage!;
        WritePackage(book, chapters, resources.Select(r => (r.Key, r.Value)).ToList(), coverName, output);
    }

    /// The flow table, or the whole text as one flow when a book has no table.
    private static List<string> ReadFlows(byte[][] records, uint fdstIndex, string text)
    {
        if (fdstIndex == NullIndex || fdstIndex >= records.Length) return [text];

        var fdst = records[fdstIndex];
        if (Encoding.ASCII.GetString(fdst, 0, 4) != "FDST") throw new MobiNotSupportedException(Damaged);
        var start = (int)U32(fdst, 4);
        var count = (int)U32(fdst, 8);

        var flows = new List<string>(count);
        for (var i = 0; i < count; i++)
        {
            var from = (int)U32(fdst, start + i * 8);
            var to = (int)U32(fdst, start + i * 8 + 4);
            flows.Add(text.Substring(from, to - from));
        }
        return flows.Count > 0 ? flows : [text];
    }

    private static (List<string> Parts, List<long> SkeletonStarts, List<Fragment> Fragments) AssembleParts(
        string text, List<IndexEntry> skeletons, List<IndexEntry> fragmentEntries)
    {
        var parts = new List<string>(skeletons.Count);
        var starts = new List<long>(skeletons.Count);
        var fragments = new List<Fragment>(fragmentEntries.Count);
        var next = 0;

        foreach (var skeleton in skeletons)
        {
            var fragmentCount = skeleton.Tags[1][0];
            var position = (int)skeleton.Tags[6][0];
            var length = (int)skeleton.Tags[6][1];

            var part = text.Substring(position, length);
            var cursor = position + length;
            for (var i = 0; i < fragmentCount; i++)
            {
                var entry = fragmentEntries[next++];
                var insertAt = long.Parse(entry.Name);
                var fragmentLength = (int)entry.Tags[6][1];
                fragments.Add(new Fragment(insertAt, parts.Count));

                var slice = text.Substring(cursor, fragmentLength);
                cursor += fragmentLength;
                part = part.Insert(SafeInsertPosition(part, insertAt - position), slice);
            }
            parts.Add(part);
            starts.Add(position);
        }
        return (parts, starts, fragments);
    }

    /// Some badly made books give a position inside a tag. Those fragments go at
    /// the end of the body, which keeps the markup valid and the text readable.
    private static int SafeInsertPosition(string part, long position)
    {
        if (position >= 0 && position <= part.Length)
        {
            var at = (int)position;
            var open = at == 0 ? -1 : part.LastIndexOf('<', at - 1);
            var close = at == 0 ? -1 : part.LastIndexOf('>', at - 1);
            if (open <= close) return at;
        }
        var bodyEnd = part.LastIndexOf("</body", StringComparison.OrdinalIgnoreCase);
        return bodyEnd >= 0 ? bodyEnd : part.Length;
    }

    private static string RewriteKindleUrls(
        string text,
        string pathToRoot,
        MobiBook book,
        List<string> flows,
        SortedDictionary<string, byte[]> resources,
        List<string> parts,
        List<long> skeletonStarts,
        List<Fragment> fragments)
    {
        text = KindlePos().Replace(text, m =>
        {
            var fragmentIndex = FromBase32(m.Groups[1].Value);
            var offset = FromBase32(m.Groups[2].Value);
            if (fragmentIndex < 0 || fragmentIndex >= fragments.Count) return "#";

            var target = fragments[(int)fragmentIndex];
            var inPart = target.InsertAt + offset - skeletonStarts[target.File];
            var id = FindIdAt(parts[target.File], inPart);
            return pathToRoot + ChapterFile(target.File) + (id is null ? "" : $"#{id}");
        });

        text = KindleEmbed().Replace(text, m =>
        {
            var index = FromBase32(m.Groups[1].Value);
            if (index is < 1 or > int.MaxValue) return "";
            var data = book.ImageForRecIndex((int)index);
            // Fonts are stored here too, obfuscated. The reader sets its own font.
            if (data is null) return "";
            var name = $"images/{index:D5}{ImageExtension(data)}";
            resources[name] = data;
            return pathToRoot + name;
        });

        return KindleFlow().Replace(text, m =>
        {
            var index = FromBase32(m.Groups[1].Value);
            if (index < 0 || index >= flows.Count) return "";
            var isSvg = m.Groups[2].Value.Contains("svg", StringComparison.OrdinalIgnoreCase);
            var name = isSvg ? $"images/flow{index:D4}.svg" : $"styles/flow{index:D4}.css";
            if (!resources.ContainsKey(name))
            {
                // Reserved first, so flows that refer to each other can't loop.
                resources[name] = [];
                var rewritten = RewriteKindleUrls(flows[(int)index], "../", book, flows, resources, parts, skeletonStarts, fragments);
                resources[name] = Encoding.Latin1.GetBytes(rewritten);
            }
            return pathToRoot + name;
        });
    }

    /// The id to link to for a byte position: on the tag at or after it, otherwise
    /// the closest one before it.
    private static string? FindIdAt(string part, long position)
    {
        if (position < 0 || position > part.Length) return null;
        var at = (int)position;

        var nextTag = part.IndexOf('<', at);
        if (nextTag >= 0)
        {
            var tagEnd = part.IndexOf('>', nextTag);
            if (tagEnd > nextTag)
            {
                var own = IdAttribute().Match(part, nextTag, tagEnd - nextTag);
                if (own.Success) return own.Groups[2].Value;
            }
        }
        var before = IdAttribute().Matches(part[..at]);
        return before.Count > 0 ? before[^1].Groups[2].Value : null;
    }

    private static long FromBase32(string digits)
    {
        long value = 0;
        foreach (var c in digits)
        {
            var digit = c is >= '0' and <= '9' ? c - '0' : char.ToUpperInvariant(c) - 'A' + 10;
            value = checked(value * 32 + digit);
        }
        return value;
    }

    // ── Index records ───────────────────────────────────────────────────────

    /// Reads an index: a header record describing the row layout, then records of rows.
    private static List<IndexEntry> ReadIndex(byte[][] records, uint indexRecord)
    {
        if (indexRecord == NullIndex || indexRecord >= records.Length)
            throw new MobiNotSupportedException(Damaged);

        var head = records[indexRecord];
        RequireSignature(head, "INDX");
        var recordCount = U32(head, 24);
        var (controlBytes, tags) = ReadTagTable(head, (int)U32(head, 180));

        var entries = new List<IndexEntry>();
        for (long r = indexRecord + 1L; r <= indexRecord + (long)recordCount; r++)
        {
            var data = records[r];
            RequireSignature(data, "INDX");
            var table = (int)U32(data, 20);
            var count = (int)U32(data, 24);
            RequireSignature(data, "IDXT", table);

            for (var i = 0; i < count; i++)
            {
                var start = U16(data, table + 4 + i * 2);
                var end = i + 1 < count ? U16(data, table + 4 + (i + 1) * 2) : table;
                entries.Add(ReadEntry(data.AsSpan(start, end - start), controlBytes, tags));
            }
        }
        return entries;
    }

    private static void RequireSignature(byte[] data, string signature, int offset = 0)
    {
        if (Encoding.ASCII.GetString(data, offset, 4) != signature)
            throw new MobiNotSupportedException(Damaged);
    }

    private readonly record struct TagInfo(int Tag, int ValuesPerEntry, int Mask, bool EndOfControlByte);

    private static (int ControlBytes, List<TagInfo> Tags) ReadTagTable(byte[] data, int offset)
    {
        RequireSignature(data, "TAGX", offset);
        var length = (int)U32(data, offset + 4);
        var controlBytes = (int)U32(data, offset + 8);

        var tags = new List<TagInfo>();
        for (var i = offset + 12; i < offset + length; i += 4)
            tags.Add(new TagInfo(data[i], data[i + 1], data[i + 2], data[i + 3] == 1));
        return (controlBytes, tags);
    }

    private static IndexEntry ReadEntry(ReadOnlySpan<byte> row, int controlByteCount, List<TagInfo> tags)
    {
        var nameLength = row[0];
        var name = Encoding.ASCII.GetString(row.Slice(1, nameLength));
        var pos = 1 + nameLength;
        var controlAt = pos;
        pos += controlByteCount;

        // Control bytes say which tags this row has, and how many values each holds.
        var present = new List<(TagInfo Tag, int? Count, int? ByteLength)>();
        foreach (var tag in tags)
        {
            if (tag.EndOfControlByte)
            {
                controlAt++;
                continue;
            }
            var value = row[controlAt] & tag.Mask;
            if (value == 0) continue;

            if (value == tag.Mask)
            {
                if (System.Numerics.BitOperations.PopCount((uint)tag.Mask) > 1)
                {
                    // All bits set on a multi-bit mask: a byte length follows instead of a count.
                    var byteLength = ReadVarInt(row, ref pos);
                    present.Add((tag, null, (int)byteLength));
                }
                else
                {
                    present.Add((tag, 1, null));
                }
            }
            else
            {
                var mask = tag.Mask;
                while ((mask & 1) == 0)
                {
                    mask >>= 1;
                    value >>= 1;
                }
                present.Add((tag, value, null));
            }
        }

        var values = new Dictionary<int, List<long>>();
        foreach (var (tag, count, byteLength) in present)
        {
            var list = new List<long>();
            if (count is { } n)
            {
                for (var i = 0; i < n * tag.ValuesPerEntry; i++)
                    list.Add(ReadVarInt(row, ref pos));
            }
            else
            {
                var end = pos + byteLength!.Value;
                while (pos < end) list.Add(ReadVarInt(row, ref pos));
            }
            values[tag.Tag] = list;
        }
        return new IndexEntry(name, values);
    }

    /// Seven bits per byte, most significant first; the top bit marks the last byte.
    private static long ReadVarInt(ReadOnlySpan<byte> data, ref int pos)
    {
        long value = 0;
        for (var i = 0; i < 9; i++)
        {
            var b = data[pos++];
            value = (value << 7) | (uint)(b & 0x7F);
            if ((b & 0x80) != 0) return value;
        }
        throw new MobiNotSupportedException(Damaged);
    }

    [GeneratedRegex(@"kindle:pos:fid:([0-9A-Va-v]+):off:([0-9A-Va-v]+)")]
    private static partial Regex KindlePos();
    [GeneratedRegex(@"kindle:embed:([0-9A-Va-v]+)(?:\?[^""')\s>]*)?")]
    private static partial Regex KindleEmbed();
    [GeneratedRegex(@"kindle:flow:([0-9A-Va-v]+)(?:\?mime=([^""')\s>]*))?")]
    private static partial Regex KindleFlow();
    [GeneratedRegex(@"\b(id|name)\s*=\s*[""']([^""']+)[""']", RegexOptions.IgnoreCase)]
    private static partial Regex IdAttribute();
}
