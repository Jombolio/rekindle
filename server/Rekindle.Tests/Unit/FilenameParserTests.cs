using FluentAssertions;
using Rekindle.Core.Services;
using Xunit;

namespace Rekindle.Tests.Unit;

public class FilenameParserTests
{
    [Theory]
    [InlineData("Berserk v01.cbz", "Berserk", 1)]
    [InlineData("One Piece v123 (2020).cbz", "One Piece", 123)]
    [InlineData("Attack on Titan Vol.1.cbz", "Attack on Titan", 1)]
    [InlineData("My Hero Academia Vol. 3.cbz", "My Hero Academia", 3)]
    public void Parse_VolumePattern_ExtractsSeriesAndVolume(string filename, string expectedSeries, int expectedVolume)
    {
        var result = FilenameParser.Parse(filename);

        result.Series.Should().Be(expectedSeries);
        result.Volume.Should().Be(expectedVolume);
    }

    [Theory]
    [InlineData("Amazing Spider-Man #001.cbz", "Amazing Spider-Man", 1)]
    [InlineData("X-Men #042.cbz", "X-Men", 42)]
    public void Parse_IssuePattern_ExtractsSeriesAndIssue(string filename, string expectedSeries, int expectedIssue)
    {
        var result = FilenameParser.Parse(filename);

        result.Series.Should().Be(expectedSeries);
        result.Volume.Should().Be(expectedIssue);
    }

    [Theory]
    [InlineData("Naruto 001 - Chapter Title.cbz", "Naruto", 1)]
    [InlineData("Bleach 032 - The Soul Reaper.cbz", "Bleach", 32)]
    public void Parse_SequencePattern_ExtractsSeriesAndNumber(string filename, string expectedSeries, int expectedNum)
    {
        var result = FilenameParser.Parse(filename);

        result.Series.Should().Be(expectedSeries);
        result.Volume.Should().Be(expectedNum);
    }

    [Theory]
    [InlineData("The Name of the Wind - Patrick Rothfuss.epub")]
    [InlineData("Some Standalone Book.pdf")]
    [InlineData("no_pattern_here.cbz")]
    public void Parse_NoPattern_ReturnsNullSeriesAndVolume(string filename)
    {
        var result = FilenameParser.Parse(filename);

        result.Series.Should().BeNull();
        result.Volume.Should().BeNull();
    }

    [Fact]
    public void Parse_AlwaysReturnsTitle_FromFilenameWithoutExtension()
    {
        var result = FilenameParser.Parse("Dune - Frank Herbert.epub");

        result.Title.Should().Be("Dune - Frank Herbert");
    }
}
