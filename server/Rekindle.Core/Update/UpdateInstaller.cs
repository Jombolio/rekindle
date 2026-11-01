using System.IO.Compression;

namespace Rekindle.Core.Update;

public sealed record InstallResult(
    IReadOnlyList<string> Replaced,
    IReadOnlyList<string> Added,
    IReadOnlyList<string> KeptExisting,
    IReadOnlyList<string> PendingCleanup);

/// <summary>
/// Installs a server release zip over an existing installation, touching only
/// the files the zip ships. Configuration and data are never overwritten:
/// <list type="bullet">
/// <item>appsettings*.json is installed only if it doesn't exist yet;</item>
/// <item>the data and cache directories are off limits, and a zip that would
/// write into them is rejected;</item>
/// <item>every other file in the install directory is left alone.</item>
/// </list>
/// Replaced files are renamed aside rather than overwritten, which works even
/// for a running executable on Windows; anything still locked is deleted by
/// <see cref="CleanupLeftovers"/> on the next start. A failure part-way through
/// rolls every change back.
/// </summary>
public static class UpdateInstaller
{
    private const string BackupSuffix = ".rekindle-old";
    private const string StagingDirName = ".rekindle-update";
    private const string LeftoversFileName = ".rekindle-update-leftovers";

    /// Executables that need the execute bit on Unix if the zip didn't carry it.
    private static readonly string[] Executables = ["Rekindle.Server"];

    public static InstallResult Install(string zipPath, string installDir, IEnumerable<string> protectedDirs)
    {
        installDir = Path.GetFullPath(installDir);
        var guarded = protectedDirs.Select(d => EnsureTrailingSeparator(Path.GetFullPath(d))).ToList();
        var staging = Path.Combine(installDir, StagingDirName);

        if (Directory.Exists(staging)) Directory.Delete(staging, recursive: true);
        Directory.CreateDirectory(staging);

        try
        {
            var files = Extract(zipPath, staging);
            return Apply(files, staging, installDir, guarded);
        }
        finally
        {
            TryDeleteDirectory(staging);
        }
    }

    /// Deletes backups an earlier update couldn't remove (e.g. the Windows
    /// executable that was running at the time). Safe to call on every start.
    public static void CleanupLeftovers(string installDir)
    {
        var list = Path.Combine(installDir, LeftoversFileName);
        if (!File.Exists(list)) return;

        var remaining = File.ReadAllLines(list)
            .Where(p => !string.IsNullOrWhiteSpace(p) && !TryDeleteFile(p))
            .ToList();

        if (remaining.Count == 0) TryDeleteFile(list);
        else File.WriteAllLines(list, remaining);
    }

    /// Extracts every file entry, refusing any that would land outside staging.
    /// Returns (relative path, unix mode from the zip or null).
    private static List<(string Relative, UnixFileMode? Mode)> Extract(string zipPath, string staging)
    {
        var root = EnsureTrailingSeparator(Path.GetFullPath(staging));
        var files = new List<(string, UnixFileMode?)>();

        using var zip = ZipFile.OpenRead(zipPath);
        foreach (var entry in zip.Entries)
        {
            if (entry.FullName.EndsWith('/') || entry.FullName.EndsWith('\\')) continue; // directory

            var relative = entry.FullName.Replace('\\', '/').TrimStart('/');
            var target = Path.GetFullPath(Path.Combine(staging, relative));
            if (Path.IsPathRooted(entry.FullName) || !target.StartsWith(root, PathComparison))
                throw new InvalidDataException($"Release archive entry '{entry.FullName}' points outside the install directory.");

            Directory.CreateDirectory(Path.GetDirectoryName(target)!);
            entry.ExtractToFile(target, overwrite: true);

            // Zips made on Unix store the file mode in the high 16 bits.
            var mode = (entry.ExternalAttributes >> 16) & 0x1FF;
            files.Add((relative, mode != 0 ? (UnixFileMode)mode : null));
        }

        if (files.Count == 0) throw new InvalidDataException("The release archive is empty.");
        return files;
    }

    private static InstallResult Apply(
        List<(string Relative, UnixFileMode? Mode)> files, string staging, string installDir, List<string> guarded)
    {
        var replaced = new List<string>();
        var added = new List<string>();
        var kept = new List<string>();
        var backups = new List<(string Target, string Backup)>();
        var newFiles = new List<string>();

        // Check everything before changing anything.
        foreach (var (relative, _) in files)
        {
            var target = Path.GetFullPath(Path.Combine(installDir, relative));
            if (guarded.Any(g => target.StartsWith(g, PathComparison)))
                throw new InvalidDataException(
                    $"Release archive contains '{relative}', inside the data or cache directory; refusing to install it.");
        }

        try
        {
            foreach (var (relative, zipMode) in files)
            {
                var staged = Path.Combine(staging, relative);
                var target = Path.GetFullPath(Path.Combine(installDir, relative));

                if (File.Exists(target) && IsConfiguration(relative))
                {
                    kept.Add(relative);
                    continue;
                }

                Directory.CreateDirectory(Path.GetDirectoryName(target)!);

                UnixFileMode? existingMode = null;
                if (File.Exists(target))
                {
                    if (!OperatingSystem.IsWindows()) existingMode = File.GetUnixFileMode(target);
                    var backup = target + BackupSuffix;
                    TryDeleteFile(backup);
                    File.Move(target, backup);
                    backups.Add((target, backup));
                    replaced.Add(relative);
                }
                else
                {
                    added.Add(relative);
                }

                File.Move(staged, target);
                newFiles.Add(target);

                if (!OperatingSystem.IsWindows())
                {
                    var mode = existingMode ?? zipMode ?? DefaultMode(relative);
                    File.SetUnixFileMode(target, mode);
                }
            }
        }
        catch
        {
            Rollback(newFiles, backups);
            throw;
        }

        // Committed. Remove backups; whatever is locked waits for the next start.
        var pending = backups.Where(b => !TryDeleteFile(b.Backup)).Select(b => b.Backup).ToList();
        var listPath = Path.Combine(installDir, LeftoversFileName);
        if (pending.Count > 0) File.AppendAllLines(listPath, pending);

        return new InstallResult(replaced, added, kept, pending);
    }

    private static void Rollback(List<string> newFiles, List<(string Target, string Backup)> backups)
    {
        foreach (var file in newFiles) TryDeleteFile(file);
        foreach (var (target, backup) in backups)
        {
            try { File.Move(backup, target, overwrite: true); }
            catch { /* best effort: the backup stays next to it for manual recovery */ }
        }
    }

    /// The user's settings: appsettings.json and appsettings.*.json at the root.
    private static bool IsConfiguration(string relative)
    {
        if (relative.Contains('/')) return false;
        return relative.Equals("appsettings.json", StringComparison.OrdinalIgnoreCase)
            || (relative.StartsWith("appsettings.", StringComparison.OrdinalIgnoreCase)
                && relative.EndsWith(".json", StringComparison.OrdinalIgnoreCase));
    }

    private static UnixFileMode DefaultMode(string relative)
    {
        const UnixFileMode readable = UnixFileMode.UserRead | UnixFileMode.UserWrite
                                      | UnixFileMode.GroupRead | UnixFileMode.OtherRead;
        return Executables.Contains(relative)
            ? readable | UnixFileMode.UserExecute | UnixFileMode.GroupExecute | UnixFileMode.OtherExecute
            : readable;
    }

    private static StringComparison PathComparison =>
        OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;

    private static string EnsureTrailingSeparator(string path) =>
        path.EndsWith(Path.DirectorySeparatorChar) ? path : path + Path.DirectorySeparatorChar;

    private static bool TryDeleteFile(string path)
    {
        try
        {
            if (File.Exists(path)) File.Delete(path);
            return true;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            return false;
        }
    }

    private static void TryDeleteDirectory(string path)
    {
        try { if (Directory.Exists(path)) Directory.Delete(path, recursive: true); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
    }
}
