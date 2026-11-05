using System.Text;
using System.Text.RegularExpressions;
using Rekindle.Core.Repositories;

namespace Rekindle.Core.Services;

public enum BookImportStatus
{
    Ready,
    AlreadyInLibrary,
    DrmProtected,
    UnsupportedFormat,
    Unreadable,
}

public sealed record BookInspection(BookImportStatus Status, string? Title, string? Author, string? Reason);

/// Decides whether a book a user wants to import can be, from the start of the
/// file alone. Protected books are only ever reported: nothing here reads past
/// their metadata, and they are never uploaded.
public static partial class BookImportInspector
{
    /// More than a client needs to send: a book's first record comes straight
    /// after the record table, which takes 8 bytes per record.
    public const int MaxHeadBytes = 1024 * 1024;

    public const string DrmReason = "This book is protected by DRM, so it can't be imported.";
    public const string KfxReason = "This book is in KFX format, which Rekindle can't read, so it can't be imported.";
    public const string TopazReason = "This book is in Topaz format, which Rekindle can't read, so it can't be imported.";
    public const string UnreadableReason = "This file couldn't be read as a book. It may be damaged.";

    private static readonly byte[] DrmIonMagic = [0xEA, .. "DRMION"u8, 0xEE];

    public static BookInspection Inspect(
        string fileName, byte[] head, string? titleHint, string? authorHint, IReadOnlyList<BookName> existing)
    {
        var extension = Path.GetExtension(fileName).TrimStart('.').ToLowerInvariant();

        switch (extension)
        {
            case "kfx":
                return new(BookImportStatus.UnsupportedFormat, null, null, KfxReason);
            case "epub":
                return Finish(fileName, titleHint, authorHint, existing);
            case "mobi" or "azw" or "azw3":
                break;
            default:
                return new(BookImportStatus.UnsupportedFormat, null, null,
                    $"Rekindle can't import .{extension} files.");
        }

        // Newer Kindle books can be other containers under a .azw name.
        var magic = head.AsSpan();
        if (magic.StartsWith(DrmIonMagic))
            return new(BookImportStatus.DrmProtected, null, null, DrmReason);
        if (magic.StartsWith("CONT"u8))
            return new(BookImportStatus.UnsupportedFormat, null, null, KfxReason);
        if (magic.StartsWith("TPZ"u8))
            return new(BookImportStatus.UnsupportedFormat, null, null, TopazReason);

        MobiHeaderInfo info;
        try
        {
            info = MobiConverter.ReadHeaderInfo(head);
        }
        catch (MobiNotSupportedException)
        {
            return new(BookImportStatus.Unreadable, null, null, UnreadableReason);
        }

        return info.IsEncrypted
            ? new(BookImportStatus.DrmProtected, info.Title, info.Author, DrmReason)
            : Finish(fileName, info.Title, info.Author, existing);
    }

    private static BookInspection Finish(
        string fileName, string? title, string? author, IReadOnlyList<BookName> existing)
    {
        var stem = Normalize(Path.GetFileNameWithoutExtension(fileName));
        var wanted = Normalize(title);

        foreach (var book in existing)
        {
            if (book.FileName.Equals(fileName, StringComparison.OrdinalIgnoreCase))
                return new(BookImportStatus.AlreadyInLibrary, title, author, "A file with this name is already in this library.");

            var existingStem = Normalize(Path.GetFileNameWithoutExtension(book.FileName));
            var existingTitle = Normalize(book.Title);
            if ((stem.Length > 0 && (stem == existingStem || stem == existingTitle))
                || (wanted.Length > 0 && (wanted == existingStem || wanted == existingTitle)))
                return new(BookImportStatus.AlreadyInLibrary, title, author, "A book with this title is already in this library.");
        }
        return new(BookImportStatus.Ready, title, author, null);
    }

    /// Compares names by their letters and digits alone, without the store id
    /// Kindle adds to file names, so "Dune_B00B7NPRY8" matches "Dune".
    private static string Normalize(string? name)
    {
        if (string.IsNullOrWhiteSpace(name)) return string.Empty;
        var sb = new StringBuilder(name.Length);
        foreach (var c in KindleIdSuffix().Replace(name, string.Empty))
            if (char.IsLetterOrDigit(c)) sb.Append(char.ToLowerInvariant(c));
        return sb.ToString();
    }

    [GeneratedRegex(@"[_-]B[0-9A-Z]{9}(?:_[A-Z]{4})?$")]
    private static partial Regex KindleIdSuffix();
}
