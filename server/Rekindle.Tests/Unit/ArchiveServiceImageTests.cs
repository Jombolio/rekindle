using System.Buffers.Binary;
using System.IO.Compression;
using System.Text;
using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using NetVips;
using Rekindle.Core.Services;
using Xunit;

namespace Rekindle.Tests.Unit;

/// Exercises the parts of ArchiveService that decode images (spread
/// detection, cover selection, PDF rendering) against real archive files.
public class ArchiveServiceImageTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), $"rekindle-archive-{Guid.NewGuid():N}");
    private readonly ArchiveService _sut;

    public ArchiveServiceImageTests()
    {
        Directory.CreateDirectory(_root);
        _sut = new ArchiveService(
            Options.Create(new RekindleOptions { CachePath = Path.Combine(_root, "cache") }),
            NullLogger<ArchiveService>.Instance);
    }

    public void Dispose()
    {
        if (Directory.Exists(_root))
            Directory.Delete(_root, recursive: true);
    }

    private static byte[] Jpeg(int width, int height, int grey = 128)
    {
        using var image = (Image.Black(width, height, bands: 3) + grey).Cast(Enums.BandFormat.Uchar);
        return image.JpegsaveBuffer();
    }

    private static byte[] Png(int width, int height)
    {
        using var image = (Image.Black(width, height, bands: 3) + 64).Cast(Enums.BandFormat.Uchar);
        return image.PngsaveBuffer();
    }

    /// Header-only BMP: enough for dimension parsing, not a decodable image.
    private static byte[] BmpHeader(int width, int height)
    {
        var bytes = new byte[54];
        bytes[0] = (byte)'B';
        bytes[1] = (byte)'M';
        BinaryPrimitives.WriteInt32LittleEndian(bytes.AsSpan(14), 40);
        BinaryPrimitives.WriteInt32LittleEndian(bytes.AsSpan(18), width);
        BinaryPrimitives.WriteInt32LittleEndian(bytes.AsSpan(22), height);
        return bytes;
    }

    private string Cbz(string name, params (string Entry, byte[] Data)[] entries)
    {
        var path = Path.Combine(_root, name);
        using var zip = ZipFile.Open(path, ZipArchiveMode.Create);
        foreach (var (entryName, data) in entries)
        {
            using var stream = zip.CreateEntry(entryName).Open();
            stream.Write(data);
        }
        return path;
    }

    /// A minimal valid PDF with one blank page per MediaBox size given.
    private string Pdf(string name, params (int Width, int Height)[] pages)
    {
        var objects = new List<string>
        {
            "<< /Type /Catalog /Pages 2 0 R >>",
            $"<< /Type /Pages /Kids [{string.Join(" ", pages.Select((_, i) => $"{i + 3} 0 R"))}] /Count {pages.Length} >>",
        };
        objects.AddRange(pages.Select(p => $"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {p.Width} {p.Height}] >>"));

        var pdf = new StringBuilder("%PDF-1.4\n");
        var offsets = new List<int>();
        for (var i = 0; i < objects.Count; i++)
        {
            offsets.Add(pdf.Length);
            pdf.Append($"{i + 1} 0 obj\n{objects[i]}\nendobj\n");
        }
        var xref = pdf.Length;
        pdf.Append($"xref\n0 {objects.Count + 1}\n0000000000 65535 f \n");
        foreach (var offset in offsets)
            pdf.Append($"{offset:D10} 00000 n \n");
        pdf.Append($"trailer\n<< /Size {objects.Count + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n");

        var path = Path.Combine(_root, name);
        File.WriteAllText(path, pdf.ToString(), Encoding.ASCII);
        return path;
    }

    private static (int Width, int Height, int Grey) Describe(Stream stream)
    {
        using var buffer = new MemoryStream();
        stream.CopyTo(buffer);
        using var image = Image.NewFromBuffer(buffer.ToArray());
        return (image.Width, image.Height, (int)image.Getpoint(image.Width / 2, image.Height / 2)[0]);
    }

    [Fact]
    public async Task Cbz_DetectsSpreads_IncludingBmpPages()
    {
        var cbz = Cbz("issue.cbz",
            ("01.jpg", Jpeg(800, 1200)),
            ("02.png", Png(1600, 1200)),    // landscape: spread
            ("03.bmp", BmpHeader(1600, 1000)), // BMP via header fallback: spread
            ("04.jpg", Jpeg(800, 1200)));

        var pageCount = await _sut.GetPageCountAsync("cbz", cbz);
        var spreads = await _sut.GetSpreadsAsync("cbz", cbz);

        pageCount.Should().Be(4);
        spreads.Should().Equal(false, true, true, false);
    }

    [Fact]
    public async Task Cbz_Cover_SkipsUndecodableEntries()
    {
        // Sorted first, but junk (e.g. a macOS resource fork) and a BMP that
        // libvips can't decode for a thumbnail; the real JPEG must be chosen.
        var cbz = Cbz("issue.cbz",
            ("00.jpg", "not really a jpeg"u8.ToArray()),
            ("01.bmp", BmpHeader(100, 100)),
            ("02.jpg", Jpeg(600, 900, grey: 200)));

        await using var cover = await _sut.OpenCoverStreamAsync(cbz);

        cover.Should().NotBeNull();
        var (width, height, grey) = Describe(cover!);
        (width, height).Should().Be((600, 900));
        grey.Should().BeInRange(190, 210);
    }

    [Fact]
    public async Task Cbz_Cover_PrefersCustomCoverEntry()
    {
        var cbz = Cbz("issue.cbz",
            ("01.jpg", Jpeg(600, 900, grey: 40)),
            ("cover.jpg", Jpeg(300, 450, grey: 220)));

        await using var cover = await _sut.OpenCoverStreamAsync(cbz);

        Describe(cover!).Should().Be((300, 450, 220), "cover.jpg outranks the first page");
    }

    [Fact]
    public async Task Pdf_RendersPagesToJpeg_AndDetectsSpreads()
    {
        var pdf = Pdf("book.pdf", (612, 792), (792, 612));

        var pageCount = await _sut.GetPageCountAsync("pdf", pdf);
        var spreads = await _sut.GetSpreadsAsync("pdf", pdf);
        var firstPage = await _sut.GetPagePathAsync("pdf", pdf, 0);

        pageCount.Should().Be(2);
        spreads.Should().Equal(false, true);
        using var rendered = Image.NewFromFile(firstPage!);
        rendered.Get("vips-loader").Should().Be("jpegload");
        rendered.Height.Should().BeGreaterThan(rendered.Width);
    }

    [Fact]
    public async Task Pdf_Cover_IsAJpegOfTheFirstPage()
    {
        var pdf = Pdf("book.pdf", (612, 792));

        await using var cover = await _sut.OpenCoverStreamAsync(pdf);

        cover.Should().NotBeNull();
        var (width, height, grey) = Describe(cover!);
        height.Should().BeGreaterThan(width);
        grey.Should().BeGreaterThan(245, "a blank PDF page renders white");
    }
}
