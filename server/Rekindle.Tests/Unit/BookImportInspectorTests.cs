using FluentAssertions;
using Rekindle.Core.Repositories;
using Rekindle.Core.Services;
using Rekindle.Tests.Helpers;
using Xunit;

namespace Rekindle.Tests.Unit;

public class BookImportInspectorTests
{
    private static readonly IReadOnlyList<BookName> Empty = [];

    private static byte[] Mobi(int encryption = 0, string title = "A Book", string? author = "An Author") =>
        new BookFixtures.Mobi
        {
            Text = "hello"u8.ToArray(),
            Encryption = encryption,
            Title = title,
            Author = author,
        }.Build();

    [Fact]
    public void Inspect_ReadsTitleAndAuthor_FromAPlainMobi()
    {
        var result = BookImportInspector.Inspect("book.mobi", Mobi(), null, null, Empty);

        result.Status.Should().Be(BookImportStatus.Ready);
        result.Title.Should().Be("A Book");
        result.Author.Should().Be("An Author");
        result.Reason.Should().BeNull();
    }

    [Theory]
    [InlineData(1)]
    [InlineData(2)]
    public void Inspect_ReportsDrm_ForAnEncryptedMobi(int encryption)
    {
        var result = BookImportInspector.Inspect("book.azw3", Mobi(encryption), null, null, Empty);

        result.Status.Should().Be(BookImportStatus.DrmProtected);
        result.Reason.Should().Be(BookImportInspector.DrmReason);
        // The list still has to say which book it means.
        result.Title.Should().Be("A Book");
    }

    [Fact]
    public void Inspect_ReportsDrmBeforeAnythingElse_WhenTheBookIsAlsoInTheLibrary()
    {
        var result = BookImportInspector.Inspect(
            "book.mobi", Mobi(encryption: 2), null, null, [new BookName("book.mobi", "A Book")]);

        result.Status.Should().Be(BookImportStatus.DrmProtected);
    }

    [Fact]
    public void Inspect_AgreesWithTheConverter_OnWhatIsProtected()
    {
        var path = Path.Combine(Path.GetTempPath(), $"rekindle-inspect-{Guid.NewGuid():N}.mobi");
        File.WriteAllBytes(path, Mobi(encryption: 1));
        try
        {
            BookImportInspector.Inspect("book.mobi", File.ReadAllBytes(path), null, null, Empty)
                .Status.Should().Be(BookImportStatus.DrmProtected);
            var convert = () => MobiConverter.ConvertToEpub(path, path + ".epub");
            convert.Should().Throw<MobiNotSupportedException>().WithMessage("*DRM*");
        }
        finally
        {
            File.Delete(path);
            File.Delete(path + ".epub");
        }
    }

    [Fact]
    public void Inspect_NeedsOnlyTheFirstRecord()
    {
        // The header is all a client sends: the book's text records are missing.
        var mobi = new BookFixtures.Mobi
        {
            Text = new byte[100_000],
            Encryption = 2,
            ExtraRecords = [new byte[100_000]],
        }.Build();

        var head = mobi[..2048];

        BookImportInspector.Inspect("book.mobi", head, null, null, Empty)
            .Status.Should().Be(BookImportStatus.DrmProtected);
    }

    [Fact]
    public void Inspect_CannotCallAHeadReady_WhenItStopsBeforeTheEncryptionField()
    {
        var mobi = Mobi(encryption: 2);
        var recordZero = 78 + 2 * 8;

        BookImportInspector.Inspect("book.mobi", mobi[..(recordZero + 10)], null, null, Empty)
            .Status.Should().Be(BookImportStatus.Unreadable);
    }

    [Fact]
    public void Inspect_CannotCallAHeadReady_WhenItStopsBeforeTheMobiHeader()
    {
        var mobi = Mobi();
        var recordZero = 78 + 2 * 8;

        BookImportInspector.Inspect("book.mobi", mobi[..(recordZero + 20)], null, null, Empty)
            .Status.Should().Be(BookImportStatus.Unreadable);
    }

    [Theory]
    [InlineData("book.kfx")]
    [InlineData("BOOK.KFX")]
    public void Inspect_RejectsKfx_ByExtension(string name)
    {
        var result = BookImportInspector.Inspect(name, [], null, null, Empty);

        result.Status.Should().Be(BookImportStatus.UnsupportedFormat);
        result.Reason.Should().Be(BookImportInspector.KfxReason);
    }

    [Fact]
    public void Inspect_RejectsKfx_UnderAnAzwName()
    {
        var head = "CONT\u0002\0\0\0"u8.ToArray();

        BookImportInspector.Inspect("book.azw", head, null, null, Empty)
            .Status.Should().Be(BookImportStatus.UnsupportedFormat);
    }

    [Fact]
    public void Inspect_ReportsDrm_ForAnEncryptedKfxContainerUnderAnAzwName()
    {
        byte[] head = [0xEA, .. "DRMION"u8, 0xEE, 0, 0, 0, 0];

        BookImportInspector.Inspect("book.azw", head, null, null, Empty)
            .Status.Should().Be(BookImportStatus.DrmProtected);
    }

    [Fact]
    public void Inspect_RejectsTopaz()
    {
        BookImportInspector.Inspect("book.azw", "TPZ0xxxx"u8.ToArray(), null, null, Empty)
            .Status.Should().Be(BookImportStatus.UnsupportedFormat);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(50)]
    public void Inspect_ReportsUnreadable_ForAFileThatIsNotAMobi(int length)
    {
        BookImportInspector.Inspect("book.mobi", new byte[length], null, null, Empty)
            .Status.Should().Be(BookImportStatus.Unreadable);
    }

    [Fact]
    public void Inspect_SurvivesLyingHeaderOffsets()
    {
        var mobi = Mobi();
        // Record zero's offset now points past the end of the data.
        mobi[78] = 0x7F;

        BookImportInspector.Inspect("book.mobi", mobi, null, null, Empty)
            .Status.Should().Be(BookImportStatus.Unreadable);
    }

    [Fact]
    public void Inspect_TakesAnEpubsMetadataFromTheClient()
    {
        var result = BookImportInspector.Inspect("book.epub", [], "Title", "Author", Empty);

        result.Status.Should().Be(BookImportStatus.Ready);
        result.Title.Should().Be("Title");
        result.Author.Should().Be("Author");
    }

    [Theory]
    [InlineData("Dune.mobi", "Dune.MOBI", "Other")]         // The same file name.
    [InlineData("Dune.azw3", "Dune.epub", "Other")]         // Another format of it.
    [InlineData("Dune_B00B7NPRY8.azw3", "Dune.epub", "Other")] // Kindle's name for it.
    [InlineData("x.mobi", "Dune.epub", "Other")]            // The book's title is its name.
    [InlineData("x.mobi", "y.epub", "DUNE")]                // The same title.
    public void Inspect_FindsABookTheLibraryHasAlready(string fileName, string existingFile, string existingTitle)
    {
        var result = BookImportInspector.Inspect(
            fileName, Mobi(title: "Dune"), null, null, [new BookName(existingFile, existingTitle)]);

        result.Status.Should().Be(BookImportStatus.AlreadyInLibrary);
        result.Reason.Should().NotBeNullOrEmpty();
    }

    [Fact]
    public void Inspect_DoesNotConfuseDifferentBooks()
    {
        var result = BookImportInspector.Inspect(
            "Dune Messiah.mobi", Mobi(title: "Dune Messiah"), null, null, [new BookName("Dune.epub", "Dune")]);

        result.Status.Should().Be(BookImportStatus.Ready);
    }

    [Fact]
    public void Inspect_DoesNotMatchEverything_WhenANameHasNoLettersOrDigits()
    {
        var result = BookImportInspector.Inspect(
            "___.mobi", Mobi(title: "!!!"), null, null, [new BookName("---.epub", "...")]);

        result.Status.Should().Be(BookImportStatus.Ready);
    }
}
