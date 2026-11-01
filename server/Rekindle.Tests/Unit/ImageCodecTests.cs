using System.Buffers.Binary;
using FluentAssertions;
using NetVips;
using Rekindle.Core.Utilities;
using Xunit;

namespace Rekindle.Tests.Unit;

public class ImageCodecTests : IDisposable
{
    private readonly string _tempDir = Path.Combine(Path.GetTempPath(), $"rekindle-imagecodec-{Guid.NewGuid():N}");

    public ImageCodecTests()
    {
        ImageCodec.Initialize();
        Directory.CreateDirectory(_tempDir);
    }

    public void Dispose()
    {
        if (Directory.Exists(_tempDir))
            Directory.Delete(_tempDir, recursive: true);
    }

    /// A solid grey test image encoded in the format named by [extension].
    private static byte[] Encoded(string extension, int width = 40, int height = 20)
    {
        using var image = (Image.Black(width, height, bands: 3) + 128).Cast(Enums.BandFormat.Uchar);
        return image.WriteToBuffer(extension);
    }

    /// A minimal uncompressed 24-bit BMP header. [height] is written as-is,
    /// so a negative value produces a top-down bitmap.
    private static byte[] BmpHeader(int width, int height, int dibHeaderSize = 40)
    {
        var bytes = new byte[54];
        bytes[0] = (byte)'B';
        bytes[1] = (byte)'M';
        BinaryPrimitives.WriteInt32LittleEndian(bytes.AsSpan(14), dibHeaderSize);
        if (dibHeaderSize == 12)
        {
            BinaryPrimitives.WriteUInt16LittleEndian(bytes.AsSpan(18), (ushort)width);
            BinaryPrimitives.WriteUInt16LittleEndian(bytes.AsSpan(20), (ushort)height);
        }
        else
        {
            BinaryPrimitives.WriteInt32LittleEndian(bytes.AsSpan(18), width);
            BinaryPrimitives.WriteInt32LittleEndian(bytes.AsSpan(22), height);
        }
        return bytes;
    }

    // ── Format support and the loader allowlist ────────────────────────────

    [Theory]
    [InlineData(".jpg")]
    [InlineData(".png")]
    [InlineData(".webp")]
    [InlineData(".gif")]
    public void TryGetSize_ReadsDimensions_ForPageFormats(string extension)
    {
        ImageCodec.TryGetSize(Encoded(extension, 40, 20)).Should().Be((40, 20));
    }

    [Theory]
    [InlineData(".tif")]
    [InlineData(".avif")]
    public void TryGetSize_RejectsFormatsOutsideTheAllowlist(string extension)
    {
        // libvips can decode these, but archive contents are untrusted and a
        // renamed TIFF or HEIF file must not reach libtiff or libheif.
        ImageCodec.TryGetSize(Encoded(extension)).Should().BeNull();
    }

    [Fact]
    public void TryGetSize_ReturnsNull_ForNonImageBytes()
    {
        ImageCodec.TryGetSize("not an image at all"u8.ToArray()).Should().BeNull();
    }

    [Fact]
    public void TryGetPageSize_ReadsDimensions_FromFileOnDisk()
    {
        var path = Path.Combine(_tempDir, "page.jpg");
        File.WriteAllBytes(path, Encoded(".jpg", 1200, 800));

        ImageCodec.TryGetPageSize(path).Should().Be((1200, 800));
    }

    [Fact]
    public void TryGetPageSize_FallsBackToBmpHeader()
    {
        // libvips has no BMP loader, but BMP pages still need spread detection.
        var path = Path.Combine(_tempDir, "page.bmp");
        File.WriteAllBytes(path, BmpHeader(1600, 1000));

        ImageCodec.TryGetPageSize(path).Should().Be((1600, 1000));
    }

    [Fact]
    public void TryGetPageSize_ReturnsNull_ForUnreadableFile()
    {
        var path = Path.Combine(_tempDir, "junk.jpg");
        File.WriteAllBytes(path, "junk"u8.ToArray());

        ImageCodec.TryGetPageSize(path).Should().BeNull();
    }

    // ── BMP header parsing ─────────────────────────────────────────────────

    [Fact]
    public void TryReadBmpSize_HandlesTopDownBitmaps()
    {
        ImageCodec.TryReadBmpSize(BmpHeader(300, -200)).Should().Be((300, 200));
    }

    [Fact]
    public void TryReadBmpSize_HandlesOs2Headers()
    {
        ImageCodec.TryReadBmpSize(BmpHeader(320, 240, dibHeaderSize: 12)).Should().Be((320, 240));
    }

    [Theory]
    [InlineData(0, 100)]
    [InlineData(100, 0)]
    [InlineData(-5, 100)]
    [InlineData(100, int.MinValue)]
    public void TryReadBmpSize_RejectsInvalidDimensions(int width, int height)
    {
        ImageCodec.TryReadBmpSize(BmpHeader(width, height)).Should().BeNull();
    }

    [Fact]
    public void TryReadBmpSize_RejectsNonBmpAndTruncatedInput()
    {
        ImageCodec.TryReadBmpSize(Encoded(".png")).Should().BeNull();
        ImageCodec.TryReadBmpSize(BmpHeader(10, 10).AsSpan(0, 20)).Should().BeNull();
    }

    // ── Encoding ───────────────────────────────────────────────────────────

    [Fact]
    public void EncodeBgraAsJpeg_SwapsChannelOrderToRgb()
    {
        // Pure blue in BGRA byte order: B=255, G=0, R=0, A=255.
        const int width = 16, height = 8;
        var bgra = new byte[width * height * 4];
        for (var p = 0; p < width * height; p++)
        {
            bgra[p * 4] = 255;
            bgra[p * 4 + 3] = 255;
        }

        var jpeg = ImageCodec.EncodeBgraAsJpeg(bgra, width, height);

        using var decoded = Image.NewFromBuffer(jpeg);
        decoded.Width.Should().Be(width);
        decoded.Height.Should().Be(height);
        decoded.Bands.Should().Be(3);
        var pixel = decoded.Getpoint(width / 2, height / 2);
        pixel[0].Should().BeLessThan(20, "red channel");
        pixel[1].Should().BeLessThan(20, "green channel");
        pixel[2].Should().BeGreaterThan(235, "blue channel");
    }

    [Fact]
    public void EncodeBgraAsJpeg_RendersTransparentAreasWhite()
    {
        // All-zero BGRA is what pdfium leaves where a page paints nothing.
        var jpeg = ImageCodec.EncodeBgraAsJpeg(new byte[16 * 8 * 4], 16, 8);

        using var decoded = Image.NewFromBuffer(jpeg);
        decoded.Bands.Should().Be(3);
        decoded.Getpoint(8, 4).Should().AllSatisfy(v => v.Should().BeGreaterThan(245));
    }

    [Fact]
    public void CreateJpegThumbnail_FitsWithinBox_KeepingAspectRatio()
    {
        var thumbnail = ImageCodec.CreateJpegThumbnail(Encoded(".jpg", 3000, 2000), 300, 450);

        using var decoded = Image.NewFromBuffer(thumbnail);
        decoded.Get("vips-loader").Should().Be("jpegload_buffer");
        decoded.Width.Should().Be(300);
        decoded.Height.Should().Be(200);
    }

    [Fact]
    public void CreateJpegThumbnail_DoesNotEnlargeSmallImages()
    {
        var thumbnail = ImageCodec.CreateJpegThumbnail(Encoded(".png", 120, 90), 300, 450);

        using var decoded = Image.NewFromBuffer(thumbnail);
        decoded.Width.Should().Be(120);
        decoded.Height.Should().Be(90);
    }

    [Fact]
    public void CreateJpegThumbnail_FlattensTransparencyOntoWhite()
    {
        // Fully transparent RGBA PNG: colour 0,0,0 with alpha 0.
        using var transparent = Image.Black(50, 50, bands: 4).Cast(Enums.BandFormat.Uchar)
            .Copy(interpretation: Enums.Interpretation.Srgb);
        var png = transparent.PngsaveBuffer();

        var thumbnail = ImageCodec.CreateJpegThumbnail(png, 300, 450);

        using var decoded = Image.NewFromBuffer(thumbnail);
        decoded.Bands.Should().Be(3);
        decoded.Getpoint(25, 25).Should().AllSatisfy(v => v.Should().BeGreaterThan(245));
    }
}
