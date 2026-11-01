using Rekindle.Core.Models;
using Rekindle.Core.Repositories;

namespace Rekindle.Core.Services;

/// <summary>
/// Per-user reading state for one media item, as shown on its cover.
/// </summary>
/// <param name="Progress">
/// Fraction read, 0 to 1. For an archive, its current page over its page
/// count. For a folder, the average over every archive beneath it.
/// </param>
/// <param name="IsCompleted">
/// The archive is finished, or every archive beneath the folder is.
/// </param>
/// <param name="NewCount">
/// Folders only: archives beneath it added after the user last read anything
/// in the same top-level series. Zero for a series the user never opened.
/// </param>
/// <param name="IsNew">
/// Archives inside a series only: added after the user last read anything in
/// that series, and not opened since.
/// </param>
public record ProgressSummary(
    string MediaId,
    double Progress,
    bool IsCompleted,
    int NewCount,
    bool IsNew);

/// The parts of a media row the summary needs.
public record MediaNode(
    string Id,
    string? ParentId,
    string MediaType,
    int? PageCount,
    DateTime AddedAt)
{
    public bool IsFolder => MediaType == "folder";
}

public class ProgressSummaryService(MediaRepository mediaRepository, ProgressRepository progressRepository)
{
    /// Upper bound on ids per request; a grid page or chapter list is far below it.
    public const int MaxIds = 500;

    public async Task<IReadOnlyList<ProgressSummary>> GetAsync(string userId, IReadOnlyCollection<string> mediaIds)
    {
        if (mediaIds.Count == 0)
            return [];

        // Whole libraries are loaded because a folder's summary depends on
        // every archive beneath it, and "new" on its top-level series.
        var nodes = await mediaRepository.GetNodesInLibrariesOfAsync(mediaIds);
        var progress = (await progressRepository.GetAllForUserAsync(userId))
            .ToDictionary(p => p.MediaId);

        return Summarize(nodes, progress, mediaIds);
    }

    /// <summary>
    /// Computes summaries for <paramref name="ids"/> from the given media rows
    /// and the user's progress. Ids not found in <paramref name="nodes"/> are
    /// skipped.
    /// </summary>
    public static IReadOnlyList<ProgressSummary> Summarize(
        IEnumerable<MediaNode> nodes,
        IReadOnlyDictionary<string, ReadingProgress> progress,
        IEnumerable<string> ids)
    {
        var tree = new Tree(nodes, progress);
        var result = new List<ProgressSummary>();

        foreach (var id in ids.Distinct())
        {
            if (!tree.Nodes.TryGetValue(id, out var node))
                continue;

            var seriesLastRead = node.ParentId is null && !node.IsFolder
                ? null // a standalone file is not part of any series
                : tree.LastReadInSeries(node);

            if (node.IsFolder)
            {
                var archives = tree.ArchivesUnder(node.Id);
                result.Add(new ProgressSummary(
                    node.Id,
                    archives.Count == 0 ? 0 : archives.Average(tree.Fraction),
                    archives.Count > 0 && archives.All(tree.IsCompleted),
                    seriesLastRead is { } since ? archives.Count(a => a.AddedAt > since) : 0,
                    IsNew: false));
            }
            else
            {
                result.Add(new ProgressSummary(
                    node.Id,
                    tree.Fraction(node),
                    tree.IsCompleted(node),
                    NewCount: 0,
                    IsNew: seriesLastRead is { } since
                           && node.AddedAt > since
                           && !progress.ContainsKey(node.Id)));
            }
        }

        return result;
    }

    private sealed class Tree
    {
        public readonly Dictionary<string, MediaNode> Nodes;
        private readonly IReadOnlyDictionary<string, ReadingProgress> _progress;
        private readonly Dictionary<string, List<MediaNode>> _children = [];
        private readonly Dictionary<string, List<MediaNode>> _archivesUnder = [];
        private readonly Dictionary<string, DateTime?> _lastReadUnder = [];

        public Tree(IEnumerable<MediaNode> nodes, IReadOnlyDictionary<string, ReadingProgress> progress)
        {
            // Database timestamps come back without a kind; they are all
            // written as UTC, so restore that before comparing them.
            Nodes = nodes
                .Select(n => n with { AddedAt = DateTime.SpecifyKind(n.AddedAt, DateTimeKind.Utc) })
                .ToDictionary(n => n.Id);
            _progress = progress;

            foreach (var node in Nodes.Values)
            {
                if (node.ParentId is null) continue;
                if (!_children.TryGetValue(node.ParentId, out var list))
                    _children[node.ParentId] = list = [];
                list.Add(node);
            }
        }

        public bool IsCompleted(MediaNode archive) =>
            _progress.TryGetValue(archive.Id, out var p) && p.IsCompleted;

        public double Fraction(MediaNode archive)
        {
            if (!_progress.TryGetValue(archive.Id, out var p))
                return 0;
            if (p.IsCompleted)
                return 1;
            // The page count is recorded the first time anyone opens the
            // archive, so it is known for anything with progress; without it
            // there is no meaningful fraction.
            if (archive.PageCount is not > 0)
                return 0;
            return Math.Clamp(p.CurrentPage / (double)archive.PageCount.Value, 0, 1);
        }

        /// Every archive at any depth beneath the folder.
        public List<MediaNode> ArchivesUnder(string folderId)
        {
            if (_archivesUnder.TryGetValue(folderId, out var cached))
                return cached;

            var result = new List<MediaNode>();
            var visited = new HashSet<string> { folderId };
            var stack = new Stack<string>([folderId]);
            while (stack.Count > 0)
            {
                if (!_children.TryGetValue(stack.Pop(), out var children)) continue;
                foreach (var child in children)
                {
                    if (!visited.Add(child.Id)) continue; // guards against a cycle in bad data
                    if (child.IsFolder) stack.Push(child.Id);
                    else result.Add(child);
                }
            }

            _archivesUnder[folderId] = result;
            return result;
        }

        /// The latest time the user read anything in the node's top-level series.
        public DateTime? LastReadInSeries(MediaNode node)
        {
            var root = Root(node);
            if (_lastReadUnder.TryGetValue(root.Id, out var cached))
                return cached;

            var archives = root.IsFolder ? ArchivesUnder(root.Id) : [root];
            DateTime? latest = null;
            foreach (var archive in archives)
            {
                if (!_progress.TryGetValue(archive.Id, out var p)) continue;
                var readAt = DateTime.SpecifyKind(p.LastReadAt, DateTimeKind.Utc);
                if (latest is null || readAt > latest) latest = readAt;
            }

            _lastReadUnder[root.Id] = latest;
            return latest;
        }

        private MediaNode Root(MediaNode node)
        {
            var visited = new HashSet<string>();
            while (node.ParentId is not null
                   && Nodes.TryGetValue(node.ParentId, out var parent)
                   && visited.Add(node.Id))
            {
                node = parent;
            }
            return node;
        }
    }
}
