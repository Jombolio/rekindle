using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Rekindle.Core.Update;

/// The result of bringing an existing appsettings.json up to date: the new
/// file's text, and the settings that were added to it ("Rekindle:Contacts").
public sealed record SettingsMergeResult(string Json, IReadOnlyList<string> Added);

/// Carries an administrator's appsettings.json over to a new release. Every
/// value they have stays exactly as it is; settings the new release ships that
/// their file doesn't have yet are added with the shipped default, so new
/// options show up in the file instead of staying hidden.
public static class SettingsMerger
{
    private static readonly JsonDocumentOptions Strict = new()
    {
        CommentHandling = JsonCommentHandling.Disallow,
        AllowTrailingCommas = false,
        // The server itself refuses a key written twice, so this only skips a
        // file that wouldn't start anyway.
        AllowDuplicateProperties = false,
    };

    /// Null when there is nothing to add, or when either file can't be read as
    /// plain JSON. A file with comments or trailing commas is still valid for
    /// the server, but rewriting it would lose them, so it is left alone.
    public static SettingsMergeResult? AddMissing(string existingJson, string shippedJson)
    {
        JsonObject? existing;
        JsonObject? shipped;
        try
        {
            existing = JsonNode.Parse(existingJson, documentOptions: Strict) as JsonObject;
            shipped = JsonNode.Parse(shippedJson, documentOptions: Strict) as JsonObject;
        }
        catch (Exception e) when (e is JsonException or ArgumentException or InvalidOperationException)
        {
            // Not plain JSON, or a key written twice.
            return null;
        }
        if (existing is null || shipped is null) return null;

        var added = new List<string>();
        Merge(existing, shipped, "", added);
        if (added.Count == 0) return null;

        var newLine = existingJson.Contains("\r\n") ? "\r\n" : "\n";
        var (indentCharacter, indentSize) = DetectIndent(existingJson);
        var json = existing.ToJsonString(new JsonSerializerOptions
        {
            WriteIndented = true,
            IndentCharacter = indentCharacter,
            IndentSize = indentSize,
            NewLine = newLine,
            // Keep URLs and the like readable rather than escaping & and +.
            Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        });
        return new SettingsMergeResult(json + newLine, added);
    }

    /// Brings the settings file at [path] up to date in place, the way an update
    /// does, so it also happens after an older version's --update or a manual
    /// unzip. Null when the file doesn't exist or has nothing to add. The new
    /// text is written beside it and swapped in, so a failure never leaves a
    /// half-written file; IO errors (a read-only install folder) are the
    /// caller's to report.
    public static SettingsMergeResult? UpgradeFile(string path, string shippedJson)
    {
        if (!File.Exists(path)) return null;

        var result = AddMissing(File.ReadAllText(path), shippedJson);
        if (result is null) return null;

        var temp = path + ".rekindle-new";
        try
        {
            File.WriteAllText(temp, result.Json);
            if (!OperatingSystem.IsWindows())
                File.SetUnixFileMode(temp, File.GetUnixFileMode(path));
            File.Move(temp, path, overwrite: true);
        }
        finally
        {
            try { if (File.Exists(temp)) File.Delete(temp); }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
        }
        return result;
    }

    /// Adds what [shipped] has and [target] lacks. Configuration keys are
    /// case-insensitive, so "rekindle" in the user's file counts as "Rekindle".
    /// Arrays and plain values are the user's: they are never looked inside or
    /// changed, nor is a value whose kind differs from the shipped one.
    private static void Merge(JsonObject target, JsonObject shipped, string path, List<string> added)
    {
        foreach (var (key, shippedValue) in shipped)
        {
            var match = target.FirstOrDefault(p => string.Equals(p.Key, key, StringComparison.OrdinalIgnoreCase));
            // Reported in the user's own spelling of the key.
            var keyPath = (path.Length == 0 ? "" : path + ":") + (match.Key ?? key);

            if (match.Key is null)
            {
                target[key] = shippedValue?.DeepClone();
                added.Add(keyPath);
            }
            else if (match.Value is JsonObject targetChild && shippedValue is JsonObject shippedChild)
            {
                Merge(targetChild, shippedChild, keyPath, added);
            }
        }
    }

    /// The indent the user's file already uses, so the rewrite looks familiar.
    private static (char Character, int Size) DetectIndent(string json)
    {
        foreach (var line in json.Split('\n'))
        {
            if (line.Trim().Length == 0) continue;
            if (line[0] == '\t') return ('\t', 1);
            var spaces = line.Length - line.TrimStart(' ').Length;
            if (spaces > 0) return (' ', Math.Min(spaces, 8));
        }
        return (' ', 2);
    }
}
