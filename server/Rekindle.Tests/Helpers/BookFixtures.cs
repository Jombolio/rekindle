using System.IO.Compression;
using System.Text;

namespace Rekindle.Tests.Helpers;

/// Builds small books byte by byte, so tests pin down the file formats themselves.
public static class BookFixtures
{
    /// An EPUB with one spine entry per chapter name, plus one spine entry whose
    /// file is missing, which readers skip.
    public static void WriteEpub(string path, params string[] chapters)
    {
        using var zip = ZipFile.Open(path, ZipArchiveMode.Create);
        Add(zip, "META-INF/container.xml",
            """<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles></container>""");

        var items = string.Join("", chapters.Select((c, i) => $"""<item id="c{i}" href="{Uri.EscapeDataString(c)}" media-type="application/xhtml+xml"/>"""));
        var spine = string.Join("", chapters.Select((_, i) => $"""<itemref idref="c{i}"/>"""));
        Add(zip, "OPS/book.opf",
            $"""
            <!DOCTYPE package>
            <package xmlns="http://www.idpf.org/2007/opf"><manifest>{items}<item id="gone" href="gone.xhtml"/><item id="img" href="cover.png"/></manifest>
            <spine>{spine}<itemref idref="gone"/></spine></package>
            """);
        foreach (var chapter in chapters)
            Add(zip, $"OPS/{chapter}", $"<html><body><p>{chapter}</p></body></html>");
        Add(zip, "OPS/cover.png", "not really an image");
    }

    private static void Add(ZipArchive zip, string name, string text)
    {
        using var writer = new StreamWriter(zip.CreateEntry(name).Open());
        writer.Write(text);
    }

    public sealed class Mobi
    {
        public byte[] Text = [];
        public int Compression = 1;
        public int Encryption;
        public int Version = 6;
        public int ExtraDataFlags;
        public uint Encoding = 65001;
        public string Title = "A Book";
        public byte[][] ExtraRecords = [];
        public int? FirstImageRecord;
        public int? CoverOffset;
        public int? HuffRecord;
        public int HuffCount;
        public uint FdstRecord = 0xFFFFFFFF;
        public uint SkeletonIndex = 0xFFFFFFFF;
        public uint FragmentIndex = 0xFFFFFFFF;

        public byte[] Build()
        {
            var header = new byte[264];
            Put16(header, 0, Compression);
            Put32(header, 4, (uint)Text.Length);
            Put16(header, 8, 1);
            Put16(header, 10, 4096);
            Put16(header, 12, Encryption);
            "MOBI"u8.CopyTo(header.AsSpan(16));
            Put32(header, 20, 248);
            Put32(header, 28, Encoding);
            Put32(header, 36, (uint)Version);
            Put32(header, 108, (uint)(FirstImageRecord ?? 0));
            if (HuffRecord is { } huff)
            {
                Put32(header, 112, (uint)huff);
                Put32(header, 116, (uint)HuffCount);
            }
            Put16(header, 242, ExtraDataFlags);
            Put32(header, 0xC0, FdstRecord);
            Put32(header, 0xF8, FragmentIndex);
            Put32(header, 0xFC, SkeletonIndex);

            using var record0 = new MemoryStream();
            record0.Write(header);
            if (CoverOffset is { } cover)
            {
                Put32(header, 128, 0x40);
                record0.Position = 0;
                record0.Write(header);
                record0.Position = record0.Length;
                var exth = new byte[12 + 12];
                "EXTH"u8.CopyTo(exth);
                Put32(exth, 4, (uint)exth.Length);
                Put32(exth, 8, 1);
                Put32(exth, 12, 201);
                Put32(exth, 16, 12);
                Put32(exth, 20, (uint)cover);
                record0.Write(exth);
            }
            var titleOffset = record0.Length;
            var title = System.Text.Encoding.UTF8.GetBytes(Title);
            record0.Write(title);
            var bytes0 = record0.ToArray();
            Put32(bytes0, 84, (uint)titleOffset);
            Put32(bytes0, 88, (uint)title.Length);

            var records = new List<byte[]> { bytes0, Text };
            records.AddRange(ExtraRecords);

            using var file = new MemoryStream();
            var palm = new byte[78 + records.Count * 8];
            "BOOKMOBI"u8.CopyTo(palm.AsSpan(60));
            Put16(palm, 76, records.Count);
            var offset = (uint)palm.Length;
            for (var i = 0; i < records.Count; i++)
            {
                Put32(palm, 78 + i * 8, offset);
                offset += (uint)records[i].Length;
            }
            file.Write(palm);
            foreach (var record in records) file.Write(record);
            return file.ToArray();
        }
    }

    /// A HUFF record whose 256 one-byte codes each select dictionary phrase
    /// (255 - code), and a CDIC record holding [phrases].
    public static (byte[] Huff, byte[] Cdic) BuildHuffCdic(params string[] phrases)
    {
        const int table1 = 24;
        var table2 = table1 + 256 * 4;
        var huff = new byte[table2 + 64 * 4];
        "HUFF"u8.CopyTo(huff);
        Put32(huff, 8, table1);
        Put32(huff, 12, (uint)table2);
        for (var i = 0; i < 256; i++)
            Put32(huff, table1 + i * 4, (255u << 8) | 0x80 | 8); // maxcode 255, terminal, 8 bits

        var offsets = new List<int>();
        using var data = new MemoryStream();
        foreach (var phrase in phrases)
        {
            offsets.Add((int)data.Length);
            var bytes = Encoding.UTF8.GetBytes(phrase);
            data.WriteByte((byte)(0x80 | (bytes.Length >> 8))); // Marked as already expanded.
            data.WriteByte((byte)bytes.Length);
            data.Write(bytes);
        }
        var tableBytes = phrases.Length * 2;
        var cdic = new byte[16 + tableBytes + data.Length];
        "CDIC"u8.CopyTo(cdic);
        Put32(cdic, 4, 16);
        Put32(cdic, 8, (uint)phrases.Length);
        Put32(cdic, 12, 8);
        for (var i = 0; i < offsets.Count; i++) Put16(cdic, 16 + i * 2, offsets[i] + tableBytes);
        data.ToArray().CopyTo(cdic, 16 + tableBytes);
        return (huff, cdic);
    }

    /// A KF8 book of two files. The first file's content is split across two
    /// fragments, and it links to a stylesheet flow, an image and the second file.
    public static Mobi BuildKf8(int? skeletonLength = null)
    {
        const string skeleton0 = "<html><head><link rel=\"stylesheet\" href=\"kindle:flow:0001?mime=text/css\"/></head><body aid=\"0\"></body></html>";
        const string fragment0 = "<h1>One</h1><p id=\"f1\">first</p>";
        const string fragment1 = "<p>second</p>";
        const string skeleton1 = "<html><body></body></html>";
        const string fragment2 = "<h1>Two</h1><p id=\"f2\">caf\u00E9</p>";
        // The image and link are tucked in the first fragment's last paragraph, so
        // they survive reassembly the same way real content does.
        var link = "<a href=\"kindle:pos:fid:0002:off:000000000B\">next</a><img src=\"kindle:embed:0001?mime=image/png\"/>";
        const string css = "p { background: url(kindle:embed:0001?mime=image/png) }";

        var fragment1WithLink = fragment1 + link;
        var flow0 = Encoding.UTF8.GetBytes(skeleton0 + fragment0 + fragment1WithLink + skeleton1 + fragment2);
        var text = flow0.Concat(Encoding.UTF8.GetBytes(css)).ToArray();

        int Len(string s) => Encoding.UTF8.GetByteCount(s);
        var bodyInner = skeleton0.IndexOf("</body>", StringComparison.Ordinal);
        var s1Start = Len(skeleton0) + Len(fragment0) + Len(fragment1WithLink);
        var body1Inner = skeleton1.IndexOf("</body>", StringComparison.Ordinal);

        byte[] fdst = new byte[12 + 16];
        "FDST"u8.CopyTo(fdst);
        Put32(fdst, 4, 12);
        Put32(fdst, 8, 2);
        Put32(fdst, 12, 0);
        Put32(fdst, 16, (uint)flow0.Length);
        Put32(fdst, 20, (uint)flow0.Length);
        Put32(fdst, 24, (uint)text.Length);

        // Tag 1: fragment count. Tag 6: position and length.
        var skeletonTags = new (int Tag, int Values, int Mask, int Eof)[] { (1, 1, 0x03, 0), (6, 2, 0x0C, 0), (0, 0, 0, 1) };
        var skeletonRows = new[]
        {
            Row("SKEL0000000000", 0x05, 2, 0, skeletonLength ?? Len(skeleton0)),
            Row("SKEL0000000001", 0x05, 1, s1Start, Len(skeleton1)),
        };
        // Tag 2: table of contents text. Tag 3: file. Tag 4: sequence. Tag 6: start and length.
        var fragmentTags = new (int Tag, int Values, int Mask, int Eof)[] { (2, 1, 0x01, 0), (3, 1, 0x02, 0), (4, 1, 0x04, 0), (6, 2, 0x18, 0), (0, 0, 0, 1) };
        var fragmentRows = new[]
        {
            Row(bodyInner.ToString("D10"), 0x0F, 0, 0, 0, 0, Len(fragment0)),
            Row((bodyInner + Len(fragment0)).ToString("D10"), 0x0F, 0, 0, 1, 0, Len(fragment1WithLink)),
            Row((s1Start + body1Inner).ToString("D10"), 0x0F, 0, 1, 0, 0, Len(fragment2)),
        };

        const uint first = 2;
        return new Mobi
        {
            Version = 8,
            Text = text,
            FirstImageRecord = (int)first + 5,
            FdstRecord = first,
            SkeletonIndex = first + 1,
            FragmentIndex = first + 3,
            ExtraRecords =
            [
                fdst,
                IndexHeader(skeletonTags), IndexRecord(skeletonRows),
                IndexHeader(fragmentTags), IndexRecord(fragmentRows),
                PngBytes,
            ],
        };
    }

    private static byte[] Row(string name, int control, params int[] values)
    {
        using var row = new MemoryStream();
        row.WriteByte((byte)name.Length);
        row.Write(Encoding.ASCII.GetBytes(name));
        row.WriteByte((byte)control);
        foreach (var value in values) WriteVarInt(row, value);
        return row.ToArray();
    }

    private static void WriteVarInt(Stream to, int value)
    {
        var groups = new List<byte>();
        do
        {
            groups.Insert(0, (byte)(value & 0x7F));
            value >>= 7;
        } while (value > 0);
        groups[^1] |= 0x80;
        to.Write(groups.ToArray());
    }

    private static byte[] IndexHeader((int Tag, int Values, int Mask, int Eof)[] tags)
    {
        const int tagAt = 192;
        var data = new byte[tagAt + 12 + tags.Length * 4];
        "INDX"u8.CopyTo(data);
        Put32(data, 24, 1); // One record of rows follows.
        Put32(data, 180, tagAt);
        "TAGX"u8.CopyTo(data.AsSpan(tagAt));
        Put32(data, tagAt + 4, (uint)(12 + tags.Length * 4));
        Put32(data, tagAt + 8, 1);
        for (var i = 0; i < tags.Length; i++)
        {
            var at = tagAt + 12 + i * 4;
            data[at] = (byte)tags[i].Tag;
            data[at + 1] = (byte)tags[i].Values;
            data[at + 2] = (byte)tags[i].Mask;
            data[at + 3] = (byte)tags[i].Eof;
        }
        return data;
    }

    private static byte[] IndexRecord(byte[][] rows)
    {
        const int rowsAt = 192;
        var table = rowsAt + rows.Sum(r => r.Length);
        var data = new byte[table + 4 + rows.Length * 2];
        "INDX"u8.CopyTo(data);
        Put32(data, 20, (uint)table);
        Put32(data, 24, (uint)rows.Length);
        "IDXT"u8.CopyTo(data.AsSpan(table));
        var at = rowsAt;
        for (var i = 0; i < rows.Length; i++)
        {
            Put16(data, table + 4 + i * 2, at);
            rows[i].CopyTo(data, at);
            at += rows[i].Length;
        }
        return data;
    }

    /// The bytes of a tiny PNG header, enough to be recognised as an image.
    public static readonly byte[] PngBytes = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3];

    private static void Put16(byte[] d, int o, int v)
    {
        d[o] = (byte)(v >> 8);
        d[o + 1] = (byte)v;
    }

    private static void Put32(byte[] d, int o, uint v)
    {
        d[o] = (byte)(v >> 24);
        d[o + 1] = (byte)(v >> 16);
        d[o + 2] = (byte)(v >> 8);
        d[o + 3] = (byte)v;
    }
}
