using System.Buffers.Binary;
using NetVips;

namespace Rekindle.Core.Utilities;

/// <summary>
/// The server's only entry point into image decoding and encoding (libvips via
/// NetVips). Everything image-related goes through here so the security
/// settings below apply to every call.
/// </summary>
public static class ImageCodec
{
    /// JPEG quality for generated covers and rendered PDF pages. 75 matches the
    /// ImageSharp default the server used before the switch to libvips.
    private const int JpegQuality = 75;

    /// libvips loader classes allowed to run. Archive contents are untrusted
    /// and libvips picks a loader by sniffing the bytes, not the file
    /// extension, so without this a TIFF or HEIF file renamed to .jpg would
    /// reach libtiff or libheif. Only the formats Rekindle serves as pages are
    /// unblocked. Names that don't exist in a given libvips build are ignored,
    /// which is why both PNG backends are listed.
    private static readonly string[] AllowedLoaders =
    [
        "VipsForeignLoadJpeg",
        "VipsForeignLoadPng",
        "VipsForeignLoadSpng",
        "VipsForeignLoadWebp",
        "VipsForeignLoadNsgif",
    ];

    static ImageCodec()
    {
        if (!ModuleInitializer.VipsInitialized)
            throw new InvalidOperationException(
                "libvips failed to load; the NetVips.Native files must sit next to the server executable.",
                ModuleInitializer.Exception);

        Operation.Block("VipsForeignLoad", true);
        foreach (var loader in AllowedLoaders)
            Operation.Block(loader, false);

        // Every image is opened once and discarded, so libvips' operation
        // cache would only hold memory and file handles in a long-running
        // server without ever producing a hit.
        Cache.Max = 0;
        Cache.MaxFiles = 0;
        Cache.MaxMem = 0;
    }

    /// Forces libvips to load and the settings above to apply. Call once at
    /// startup so a missing native library fails the boot, not the first scan.
    public static string Initialize() =>
        $"{NetVips.NetVips.Version(0)}.{NetVips.NetVips.Version(1)}.{NetVips.NetVips.Version(2)}";

    /// Reads the dimensions of an encoded image from its header without
    /// decoding the pixels. Returns null if no allowed loader accepts it.
    public static (int Width, int Height)? TryGetSize(byte[] data)
    {
        try
        {
            using var image = Image.NewFromBuffer(data, access: Enums.Access.Sequential);
            return (image.Width, image.Height);
        }
        catch (VipsException)
        {
            return null;
        }
    }

    /// Dimensions of an extracted page on disk, read from the header only.
    /// Falls back to parsing BMP headers by hand: libvips has no BMP loader,
    /// but BMP pages are still served to clients and need spread detection.
    public static (int Width, int Height)? TryGetPageSize(string path)
    {
        try
        {
            using var image = Image.NewFromFile(path, access: Enums.Access.Sequential);
            return (image.Width, image.Height);
        }
        catch (VipsException)
        {
            return TryReadBmpFileSize(path);
        }
    }

    private static (int Width, int Height)? TryReadBmpFileSize(string path)
    {
        Span<byte> header = stackalloc byte[26];
        using var file = File.OpenRead(path);
        var read = file.ReadAtLeast(header, header.Length, throwOnEndOfStream: false);
        return TryReadBmpSize(header[..read]);
    }

    /// Reads width and height from a BMP file header, or null if the bytes
    /// aren't a BMP. Handles both the old 12-byte OS/2 header and the 40+ byte
    /// Windows headers, where a negative height marks a top-down bitmap.
    public static (int Width, int Height)? TryReadBmpSize(ReadOnlySpan<byte> header)
    {
        if (header.Length < 26 || header[0] != (byte)'B' || header[1] != (byte)'M')
            return null;

        var dibHeaderSize = BinaryPrimitives.ReadInt32LittleEndian(header[14..]);
        int width, height;
        if (dibHeaderSize == 12)
        {
            width = BinaryPrimitives.ReadUInt16LittleEndian(header[18..]);
            height = BinaryPrimitives.ReadUInt16LittleEndian(header[20..]);
        }
        else if (dibHeaderSize >= 40)
        {
            width = BinaryPrimitives.ReadInt32LittleEndian(header[18..]);
            var rawHeight = BinaryPrimitives.ReadInt32LittleEndian(header[22..]);
            if (rawHeight == int.MinValue)
                return null;
            height = Math.Abs(rawHeight);
        }
        else
        {
            return null;
        }

        return width > 0 && height > 0 ? (width, height) : null;
    }

    /// Encodes a raw BGRA buffer (as produced by the PDF renderer) to JPEG,
    /// compositing it onto white. Pdfium leaves any area a page doesn't paint
    /// fully transparent, so simply dropping the alpha channel would turn the
    /// background of most text PDFs black.
    public static byte[] EncodeBgraAsJpeg(byte[] bgra, int width, int height)
    {
        using var raw = Image.NewFromMemory(bgra, width, height, 4, Enums.BandFormat.Uchar);
        using var blue = raw.ExtractBand(0);
        using var green = raw.ExtractBand(1);
        using var red = raw.ExtractBand(2);
        using var alpha = raw.ExtractBand(3);
        using var rgba = red.Bandjoin(green, blue, alpha).Copy(interpretation: Enums.Interpretation.Srgb);
        using var flattened = rgba.Flatten(background: [255, 255, 255]);
        return flattened.JpegsaveBuffer(q: JpegQuality);
    }

    /// Scales an encoded image down to fit within the given box, keeping its
    /// aspect ratio, and returns it as JPEG. Images already smaller than the
    /// box are not enlarged. libvips decodes JPEGs at reduced size directly
    /// ("shrink-on-load"), so large pages are cheap to thumbnail.
    public static byte[] CreateJpegThumbnail(byte[] data, int maxWidth, int maxHeight)
    {
        using var thumbnail = Image.ThumbnailBuffer(
            data, maxWidth, height: maxHeight, size: Enums.Size.Down);

        // JPEG has no alpha: flatten transparent covers onto white rather than
        // the black libvips would use. CMYK sources are converted so every
        // client renders the cover's colours the same way.
        using var flattened = thumbnail.HasAlpha()
            ? thumbnail.Flatten(background: [255, 255, 255])
            : thumbnail.Copy();
        using var output = flattened.Interpretation == Enums.Interpretation.Cmyk
            ? flattened.Colourspace(Enums.Interpretation.Srgb)
            : flattened.Copy();

        return output.JpegsaveBuffer(q: JpegQuality);
    }
}
