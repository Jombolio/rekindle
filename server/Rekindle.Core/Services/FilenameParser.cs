using System.Text.RegularExpressions;

namespace Rekindle.Core.Services;

public static partial class FilenameParser
{
    public record FileMeta(string Title, string? Series, int? Volume);

    private static readonly HashSet<string> KnownExtensions =
        [".cbz", ".cbr", ".pdf", ".epub", ".mobi"];

    public static FileMeta Parse(string filePath)
    {
        var fullName = Path.GetFileName(filePath);
        // Only strip the extension for recognised archive/book formats.
        // Using GetFileNameWithoutExtension unconditionally truncates names like
        // "DC K.O" (directory) or "Series 1.5" at the dot.
        var ext = Path.GetExtension(fullName).ToLowerInvariant();
        var name = KnownExtensions.Contains(ext)
            ? Path.GetFileNameWithoutExtension(fullName)
            : fullName;

        var volMatch = VolumePattern().Match(name);
        if (volMatch.Success)
            return new FileMeta(name, volMatch.Groups["series"].Value.Trim(), int.Parse(volMatch.Groups["vol"].Value));

        var issueMatch = IssuePattern().Match(name);
        if (issueMatch.Success)
            return new FileMeta(name, issueMatch.Groups["series"].Value.Trim(), int.Parse(issueMatch.Groups["num"].Value));

        var seqMatch = SequencePattern().Match(name);
        if (seqMatch.Success)
            return new FileMeta(name, seqMatch.Groups["series"].Value.Trim(), int.Parse(seqMatch.Groups["num"].Value));

        return new FileMeta(name, null, null);
    }

    [GeneratedRegex(@"^(?<series>.+?)\s+[vV](?:ol\.?\s*)?(?<vol>\d+)", RegexOptions.Compiled)]
    public static partial Regex VolumePattern();

    [GeneratedRegex(@"^(?<series>.+?)\s+#(?<num>\d+)", RegexOptions.Compiled)]
    public static partial Regex IssuePattern();

    [GeneratedRegex(@"^(?<series>.+?)\s+(?<num>\d{2,4})\s*-", RegexOptions.Compiled)]
    public static partial Regex SequencePattern();
}
