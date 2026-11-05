using System.IO.Compression;
using System.Text;
using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Rekindle.Core.Services;
using Rekindle.Tests.Helpers;
using Xunit;

namespace Rekindle.Tests.Unit;

public class MobiConverterTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), $"rekindle-mobi-{Guid.NewGuid():N}");
    private readonly BookService _books;

    public MobiConverterTests()
    {
        Directory.CreateDirectory(_root);
        _books = new BookService(
            Options.Create(new RekindleOptions { CachePath = Path.Combine(_root, "cache") }),
            NullLogger<BookService>.Instance);
    }

    public void Dispose() => TempCleanup.DeleteDirectory(_root);

    private string Write(BookFixtures.Mobi mobi, string name = "book.mobi")
    {
        var path = Path.Combine(_root, name);
        File.WriteAllBytes(path, mobi.Build());
        return path;
    }

    private string Convert(BookFixtures.Mobi mobi)
    {
        var epub = Path.Combine(_root, $"{Guid.NewGuid():N}.epub");
        MobiConverter.ConvertToEpub(Write(mobi), epub);
        return epub;
    }

    private static string ReadEntry(string epub, string name)
    {
        using var zip = ZipFile.OpenRead(epub);
        using var reader = new StreamReader(zip.GetEntry(name)!.Open());
        return reader.ReadToEnd();
    }

    private static BookFixtures.Mobi Plain(string html) => new() { Text = Encoding.UTF8.GetBytes(html) };

    [Fact]
    public void PageBreaks_BecomeChapters()
    {
        var epub = Convert(Plain(
            "<html><head><guide></guide></head><body><h1>One</h1><p>a</p><mbp:pagebreak/><h2>Two</h2><p>b</p><mbp:pagebreak/></body></html>"));

        _books.CountChapters(epub).Should().Be(2);
        ReadEntry(epub, "OEBPS/part0000.html").Should().Contain("<title>One</title>").And.Contain("<p>a</p>");
        ReadEntry(epub, "OEBPS/part0001.html").Should().Contain("<title>Two</title>").And.NotContain("mbp:");
    }

    [Fact]
    public void EpubStartsWithUncompressedMimetype()
    {
        using var zip = ZipFile.OpenRead(Convert(Plain("<p>a</p>")));
        var first = zip.Entries[0];
        first.FullName.Should().Be("mimetype");
        first.CompressedLength.Should().Be(first.Length);
    }

    [Fact]
    public void FilePosLinks_PointAtTheChapterHoldingTheirTarget()
    {
        const string before = "<p><a filepos=0000000000>go</a></p><mbp:pagebreak/>";
        var target = Encoding.UTF8.GetByteCount(before);
        var html = before.Replace("0000000000", target.ToString("D10")) + "<p>target</p>";

        var epub = Convert(Plain(html));

        ReadEntry(epub, "OEBPS/part0000.html").Should().Contain($"href=\"part0001.html#fp{target}\"");
        ReadEntry(epub, "OEBPS/part0001.html").Should().Contain($"<a id=\"fp{target}\"></a><p>target</p>");
    }

    [Fact]
    public void FilePosTarget_InsideATag_MovesInFrontOfIt()
    {
        var anchored = MobiConverter.InsertFilePosAnchors("<a filepos=15>x</a><p>y</p>");
        anchored.Should().StartWith("<a filepos=15>");
        anchored.Should().Contain("<a id=\"fp15\"></a>");
        // Offset 15 is just past "<a filepos=15>x": never splitting a tag.
        anchored.Should().NotContain("<a id=\"fp15\"></a>p>");
    }

    [Fact]
    public void Images_AreCarriedOverAndLinked()
    {
        var mobi = Plain("<p><img recindex=\"00001\"></p>");
        mobi.FirstImageRecord = 2;
        mobi.ExtraRecords = [BookFixtures.PngBytes];

        var epub = Convert(mobi);

        ReadEntry(epub, "OEBPS/part0000.html").Should().Contain("src=\"images/00001.png\"");
        using var zip = ZipFile.OpenRead(epub);
        zip.GetEntry("OEBPS/images/00001.png").Should().NotBeNull();
    }

    [Fact]
    public void PalmDocCompression_IsExpanded()
    {
        // "abcabc" via a back-reference, then " x" via the space+char code.
        byte[] compressed = [(byte)'a', (byte)'b', (byte)'c', 0x80, (3 << 3) | 0, (byte)('x' ^ 0x80)];
        var output = new MemoryStream();

        MobiConverter.DecompressPalmDoc(compressed, output);

        Encoding.ASCII.GetString(output.ToArray()).Should().Be("abcabc x");
    }

    [Fact]
    public void HuffCdicCompression_IsExpanded()
    {
        var (huff, cdic) = BookFixtures.BuildHuffCdic("<p>hello ", "world</p>");
        var mobi = new BookFixtures.Mobi
        {
            Compression = 17480,
            Text = [255, 254],  // Codes selecting phrases 0 and 1.
            ExtraRecords = [huff, cdic],
            HuffRecord = 2,
            HuffCount = 2,
        };

        ReadEntry(Convert(mobi), "OEBPS/part0000.html").Should().Contain("<p>hello world</p>");
    }

    [Fact]
    public void TrailingData_IsNotTreatedAsText()
    {
        // Flag bit 1 = one trailing entry; its size (3, including itself) is the last byte.
        var mobi = Plain("<p>real</p>");
        mobi.Text = [.. mobi.Text, (byte)'X', (byte)'X', 0x83];
        mobi.ExtraDataFlags = 0b10;

        ReadEntry(Convert(mobi), "OEBPS/part0000.html").Should().Contain("<p>real</p>").And.NotContain("XX");
    }

    [Fact]
    public void Windows1252Text_IsDecoded()
    {
        var mobi = new BookFixtures.Mobi
        {
            Encoding = 1252,
            Text = [.. "<p>it"u8, 0x92, .. "s caf"u8, 0xE9, .. "</p>"u8],
        };

        ReadEntry(Convert(mobi), "OEBPS/part0000.html").Should().Contain("<p>it’s café</p>");
    }

    [Fact]
    public void DrmProtectedBook_IsRejectedWithAReason()
    {
        var act = () => Convert(new BookFixtures.Mobi { Text = "<p>a</p>"u8.ToArray(), Encryption = 2 });
        act.Should().Throw<MobiNotSupportedException>().WithMessage("*DRM*");
    }

    [Fact]
    public void Kf8Book_ReassemblesFragmentsIntoTheirFiles()
    {
        var epub = Convert(BookFixtures.BuildKf8());

        _books.CountChapters(epub).Should().Be(2);
        ReadEntry(epub, "OEBPS/part0000.html").Should()
            .Contain("<body aid=\"0\"><h1>One</h1><p id=\"f1\">first</p><p>second</p>");
        ReadEntry(epub, "OEBPS/part0001.html").Should().Contain("<h1>Two</h1>");
    }

    [Fact]
    public void Kf8Book_RewritesKindleLinks()
    {
        var epub = Convert(BookFixtures.BuildKf8());
        var first = ReadEntry(epub, "OEBPS/part0000.html");

        first.Should().NotContain("kindle:");
        first.Should().Contain("href=\"styles/flow0001.css\"");
        first.Should().Contain("src=\"images/00001.png\"");
        first.Should().Contain("href=\"part0001.html#f2\"");

        // A stylesheet sits one folder down, so its image link climbs back up.
        ReadEntry(epub, "OEBPS/styles/flow0001.css").Should().Contain("url(../images/00001.png)");
        using var zip = ZipFile.OpenRead(epub);
        zip.GetEntry("OEBPS/images/00001.png").Should().NotBeNull();
    }

    [Fact]
    public void Kf8Book_IsDecodedAsUtf8()
    {
        ReadEntry(Convert(BookFixtures.BuildKf8()), "OEBPS/part0001.html").Should().Contain("caf\u00E9");
    }

    [Fact]
    public void Kf8Book_WithoutItsIndexes_IsRejectedAsDamaged()
    {
        var act = () => Convert(new BookFixtures.Mobi { Text = "<p>a</p>"u8.ToArray(), Version = 8 });
        act.Should().Throw<MobiNotSupportedException>().WithMessage("*damaged*");
    }

    [Fact]
    public void Kf8Book_WithALyingIndex_IsRejectedAsDamaged()
    {
        var mobi = BookFixtures.BuildKf8(skeletonLength: 999_999);
        var act = () => Convert(mobi);
        act.Should().Throw<MobiNotSupportedException>().WithMessage("*damaged*");
    }

    [Fact]
    public void NotAMobi_IsRejected()
    {
        var path = Path.Combine(_root, "fake.mobi");
        File.WriteAllBytes(path, new byte[200]);
        var act = () => MobiConverter.ConvertToEpub(path, path + ".epub");
        act.Should().Throw<MobiNotSupportedException>();
    }

    [Fact]
    public void TruncatedFile_IsRejected_NotACrash()
    {
        var full = Plain("<p>a</p>").Build();
        var path = Path.Combine(_root, "cut.mobi");
        File.WriteAllBytes(path, full[..100]);
        var act = () => MobiConverter.ConvertToEpub(path, path + ".epub");
        act.Should().Throw<MobiNotSupportedException>();
    }

    [Fact]
    public void ReadCover_ReturnsTheExthCover()
    {
        var mobi = Plain("<p>a</p>");
        mobi.FirstImageRecord = 2;
        mobi.ExtraRecords = [BookFixtures.PngBytes];
        mobi.CoverOffset = 0;

        MobiConverter.ReadCover(Write(mobi)).Should().Equal(BookFixtures.PngBytes);
    }

    [Fact]
    public void ReadCover_OnUnreadableFile_ReturnsNull()
    {
        var path = Path.Combine(_root, "junk.mobi");
        File.WriteAllBytes(path, new byte[10]);
        MobiConverter.ReadCover(path).Should().BeNull();
    }

    [Fact]
    public async Task BookService_ConvertsOnce_AndAgainWhenTheSourceChanges()
    {
        var source = Write(Plain("<p>first</p>"));

        var first = await _books.GetEpubPathAsync("m1", source);
        var firstWrite = File.GetLastWriteTimeUtc(first);
        (await _books.GetEpubPathAsync("m1", source)).Should().Be(first);
        File.GetLastWriteTimeUtc(first).Should().Be(firstWrite);

        File.WriteAllBytes(source, Plain("<p>second</p>").Build());
        File.SetLastWriteTimeUtc(source, DateTime.UtcNow.AddMinutes(1));
        var updated = await _books.GetEpubPathAsync("m1", source);

        ReadEntry(updated, "OEBPS/part0000.html").Should().Contain("second");
    }

    [Fact]
    public async Task BookService_ServesEpubFilesAsTheyAre()
    {
        var path = Path.Combine(_root, "real.epub");
        BookFixtures.WriteEpub(path, "a.xhtml");
        (await _books.GetEpubPathAsync("m2", path)).Should().Be(path);
    }

    [Fact]
    public void CountChapters_SkipsSpineEntriesWithNoFile_AndDecodesHrefs()
    {
        var path = Path.Combine(_root, "count.epub");
        BookFixtures.WriteEpub(path, "chapter 1.xhtml", "chapter 2.xhtml");
        _books.CountChapters(path).Should().Be(2);
    }

    [Fact]
    public void CountChapters_OnNonEpub_ReturnsZero()
    {
        var path = Path.Combine(_root, "junk.epub");
        File.WriteAllText(path, "not a zip");
        _books.CountChapters(path).Should().Be(0);
    }
}
