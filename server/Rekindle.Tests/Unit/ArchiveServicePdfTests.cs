using System.Text;
using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Rekindle.Core.Services;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.PixelFormats;
using Xunit;

namespace Rekindle.Tests.Unit;

/// Renders real PDF files through ArchiveService. Pdfium leaves areas a page
/// doesn't paint transparent, which used to come out black in the JPEGs.
public class ArchiveServicePdfTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), $"rekindle-pdf-{Guid.NewGuid():N}");
    private readonly ArchiveService _sut;

    public ArchiveServicePdfTests()
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

    /// A minimal valid PDF with one blank page per MediaBox size given.
    private string Pdf(params (int Width, int Height)[] pages)
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

        var path = Path.Combine(_root, "book.pdf");
        File.WriteAllText(path, pdf.ToString(), Encoding.ASCII);
        return path;
    }

    private static void ShouldBeWhiteAtCentre(Image<Rgb24> image)
    {
        var pixel = image[image.Width / 2, image.Height / 2];
        pixel.R.Should().BeGreaterThan(245);
        pixel.G.Should().BeGreaterThan(245);
        pixel.B.Should().BeGreaterThan(245);
    }

    [Fact]
    public async Task ExtractedPages_RenderBlankAreasWhite_AndDetectSpreads()
    {
        var pdf = Pdf((612, 792), (792, 612));

        var spreads = await _sut.GetSpreadsAsync("pdf", pdf);
        var firstPage = await _sut.GetPagePathAsync("pdf", pdf, 0);

        spreads.Should().Equal(false, true);
        using var image = await Image.LoadAsync<Rgb24>(firstPage!);
        image.Height.Should().BeGreaterThan(image.Width);
        ShouldBeWhiteAtCentre(image);
    }

    [Fact]
    public async Task Cover_RendersBlankAreasWhite()
    {
        var pdf = Pdf((612, 792));

        await using var cover = await _sut.OpenCoverStreamAsync(pdf);

        cover.Should().NotBeNull();
        using var image = await Image.LoadAsync<Rgb24>(cover!);
        ShouldBeWhiteAtCentre(image);
    }
}
