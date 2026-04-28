using System.Threading.Channels;
using Microsoft.Extensions.Logging;
using Rekindle.Core.Models;
using Rekindle.Core.Repositories;

namespace Rekindle.Core.Services;

public class LibraryScannerService(
    MediaRepository mediaRepository,
    Channel<CoverJob> coverQueue,
    ScanProgressTracker progressTracker,
    ILogger<LibraryScannerService> logger)
{
    public static readonly HashSet<string> SupportedExtensions =
        [".cbz", ".cbr", ".pdf", ".epub", ".mobi"];

    public async Task ScanAsync(Library library)
    {
        logger.LogInformation("Scanning library '{Name}' at {Path}", library.Name, library.RootPath);

        if (!Directory.Exists(library.RootPath))
        {
            logger.LogWarning("Library path does not exist: {Path}", library.RootPath);
            // Still create a progress entry so the client sees a fast "complete" instead of spinning.
            var empty = progressTracker.Begin(library.Id, 0);
            empty.Complete();
            return;
        }

        // Build the complete expected filesystem tree (DFS order: parents before children)
        var expected = BuildExpectedTree(library.RootPath);
        var expectedPaths = expected
            .Select(n => n.Path)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        var progress = progressTracker.Begin(library.Id, expected.Count);

        // Get all existing DB entries for this library
        var existing = (await mediaRepository.GetAllPathsForLibraryAsync(library.Id)).ToList();

        // ── Stale removal ────────────────────────────────────────────────────
        foreach (var stale in existing.Where(e => !expectedPaths.Contains(e.FilePath)))
        {
            await mediaRepository.DeleteByFilePathAsync(stale.FilePath);
            progress.RecordRemoved();
            logger.LogInformation("Removed stale entry: {Path}", stale.FilePath);
        }

        // Re-fetch after deletions so our lookup maps are accurate
        existing = (await mediaRepository.GetAllPathsForLibraryAsync(library.Id)).ToList();
        var existingByPath = existing.ToDictionary(
            e => e.FilePath, e => e, StringComparer.OrdinalIgnoreCase);

        // ── Additions + re-parenting ─────────────────────────────────────────
        var pathToId = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        foreach (var node in expected)
        {
            string? expectedParentId = null;
            if (node.ParentPath is not null)
                pathToId.TryGetValue(node.ParentPath, out expectedParentId);

            if (existingByPath.TryGetValue(node.Path, out var entry))
            {
                if (entry.ParentId != expectedParentId)
                {
                    await mediaRepository.UpdateParentAsync(entry.Id, expectedParentId);
                    logger.LogInformation("Re-parented: {Path}", node.Path);
                }
                pathToId[node.Path] = entry.Id;
            }
            else
            {
                if (node.IsDirectory)
                {
                    var newId = await AddFolderEntryAsync(library, node.Path, expectedParentId, progress);
                    if (newId is not null)
                        pathToId[node.Path] = newId;
                }
                else
                {
                    await AddArchiveAsync(library, node.Path, expectedParentId, progress);
                }
            }

            progress.RecordProcessed();
        }

        progress.Complete();
        logger.LogInformation("Scan complete for library '{Name}'", library.Name);
    }

    // ── Filesystem tree builder ──────────────────────────────────────────────

    private List<TreeNode> BuildExpectedTree(string libraryRoot)
    {
        var nodes = new List<TreeNode>();
        CollectNodes(libraryRoot, parentPath: null, nodes);
        return nodes;
    }

    private void CollectNodes(string dir, string? parentPath, List<TreeNode> nodes)
    {
        try
        {
            foreach (var file in Directory
                .EnumerateFiles(dir, "*.*", SearchOption.TopDirectoryOnly)
                .Where(IsSupported))
            {
                nodes.Add(new TreeNode(file, IsDirectory: false, ParentPath: parentPath));
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Could not enumerate files in: {Dir}", dir);
        }

        IEnumerable<string> subDirs;
        try
        {
            subDirs = Directory
                .EnumerateDirectories(dir, "*", SearchOption.TopDirectoryOnly)
                .Where(d => Directory
                    .EnumerateFiles(d, "*.*", SearchOption.AllDirectories)
                    .Any(IsSupported))
                .ToList();
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Could not enumerate subdirectories in: {Dir}", dir);
            return;
        }

        foreach (var subDir in subDirs)
        {
            nodes.Add(new TreeNode(subDir, IsDirectory: true, ParentPath: parentPath));
            CollectNodes(subDir, parentPath: subDir, nodes);
        }
    }

    // ── DB entry creators ────────────────────────────────────────────────────

    private async Task<string?> AddFolderEntryAsync(
        Library library, string dirPath, string? parentId, ScanProgress progress)
    {
        try
        {
            var sampleFiles = Directory
                .EnumerateFiles(dirPath, "*.*", SearchOption.AllDirectories)
                .Where(IsSupported)
                .ToList();

            if (sampleFiles.Count == 0) return null;

            var format = sampleFiles
                .GroupBy(f => Path.GetExtension(f).TrimStart('.').ToLowerInvariant())
                .OrderByDescending(g => g.Count())
                .First().Key;

            var meta = FilenameParser.Parse(dirPath);
            var folderId = Guid.NewGuid().ToString();

            var folder = new Media
            {
                Id = folderId,
                LibraryId = library.Id,
                ParentId = parentId,
                Title = meta.Title,
                Series = meta.Series,
                Volume = meta.Volume,
                FilePath = dirPath,
                Format = format,
                MediaType = "folder",
                RelativePath = RelativeTo(library.RootPath, dirPath),
                AddedAt = DateTime.UtcNow,
            };

            await mediaRepository.InsertAsync(folder);
            await coverQueue.Writer.WriteAsync(new CoverJob(folderId, dirPath, library.Id));

            progress.RecordFolder();
            progress.RecordCoverQueued();

            logger.LogDebug("Added folder: {Title} (parentId={ParentId})", folder.Title, parentId);
            return folderId;
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Failed to add folder: {Path}", dirPath);
            return null;
        }
    }

    private async Task AddArchiveAsync(
        Library library, string filePath, string? parentId, ScanProgress progress)
    {
        try
        {
            var meta = FilenameParser.Parse(filePath);
            var format = Path.GetExtension(filePath).TrimStart('.').ToLowerInvariant();

            var media = new Media
            {
                Id = Guid.NewGuid().ToString(),
                LibraryId = library.Id,
                ParentId = parentId,
                Title = meta.Title,
                Series = meta.Series,
                Volume = meta.Volume,
                FilePath = filePath,
                Format = format,
                MediaType = "archive",
                RelativePath = RelativeTo(library.RootPath, filePath),
                AddedAt = DateTime.UtcNow,
            };

            await mediaRepository.InsertAsync(media);
            await coverQueue.Writer.WriteAsync(new CoverJob(media.Id, filePath, library.Id));

            progress.RecordAdded();
            progress.RecordCoverQueued();

            logger.LogDebug("Added archive: {Title} ({Format})", media.Title, format);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Failed to add archive: {Path}", filePath);
        }
    }

    // ── Utilities ────────────────────────────────────────────────────────────

    private static string RelativeTo(string rootPath, string fullPath)
    {
        var root = rootPath.TrimEnd('/', '\\');
        return fullPath.StartsWith(root, StringComparison.OrdinalIgnoreCase)
            ? fullPath[(root.Length + 1)..]
            : Path.GetFileName(fullPath);
    }

    private static bool IsSupported(string path) =>
        SupportedExtensions.Contains(Path.GetExtension(path).ToLowerInvariant());

    private record TreeNode(string Path, bool IsDirectory, string? ParentPath);
}
