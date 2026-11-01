using FluentAssertions;
using Rekindle.Core.Models;
using Rekindle.Core.Services;
using Xunit;

namespace Rekindle.Tests.Unit;

public class ProgressSummaryTests
{
    private static readonly DateTime T0 = new(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc);

    private static MediaNode Archive(string id, string? parent = null, int? pages = 100, int addedDay = 0) =>
        new(id, parent, "archive", pages, T0.AddDays(addedDay));

    private static MediaNode Folder(string id, string? parent = null, int addedDay = 0) =>
        new(id, parent, "folder", null, T0.AddDays(addedDay));

    private static ReadingProgress Read(string id, int page = 0, bool completed = false, int readDay = 1) =>
        new() { MediaId = id, CurrentPage = page, IsCompleted = completed, LastReadAt = T0.AddDays(readDay) };

    private static ProgressSummary One(
        IEnumerable<MediaNode> nodes, IEnumerable<ReadingProgress> progress, string id) =>
        ProgressSummaryService
            .Summarize(nodes, progress.ToDictionary(p => p.MediaId), [id])
            .Single();

    // ── Archives ──────────────────────────────────────────────────────────

    [Fact]
    public void Archive_Unread_IsZero()
    {
        var s = One([Archive("a")], [], "a");

        s.Progress.Should().Be(0);
        s.IsCompleted.Should().BeFalse();
        s.NewCount.Should().Be(0);
        s.IsNew.Should().BeFalse();
    }

    [Fact]
    public void Archive_InProgress_IsPageOverPageCount()
    {
        One([Archive("a", pages: 40)], [Read("a", page: 10)], "a").Progress.Should().Be(0.25);
    }

    [Fact]
    public void Archive_Completed_IsOne()
    {
        var s = One([Archive("a", pages: 40)], [Read("a", page: 3, completed: true)], "a");

        s.Progress.Should().Be(1);
        s.IsCompleted.Should().BeTrue();
    }

    [Fact]
    public void Archive_UnknownPageCount_IsZeroUnlessCompleted()
    {
        One([Archive("a", pages: null)], [Read("a", page: 10)], "a").Progress.Should().Be(0);
        One([Archive("b", pages: null)], [Read("b", completed: true)], "b").Progress.Should().Be(1);
    }

    [Fact]
    public void Archive_PageBeyondCount_IsClampedToOne()
    {
        // The archive was replaced by a shorter one after the user read it.
        One([Archive("a", pages: 10)], [Read("a", page: 50)], "a").Progress.Should().Be(1);
    }

    [Fact]
    public void StandaloneArchive_IsNeverNew()
    {
        // Single files never get a "new" badge, even when added after the
        // user's last read of something else.
        var nodes = new[] { Archive("old"), Archive("fresh", addedDay: 10) };
        One(nodes, [Read("old", readDay: 5)], "fresh").IsNew.Should().BeFalse();
    }

    // ── Folders ───────────────────────────────────────────────────────────

    [Fact]
    public void Folder_Progress_AveragesItsArchives()
    {
        var nodes = new[]
        {
            Folder("s"),
            Archive("c1", "s", pages: 10),
            Archive("c2", "s", pages: 10),
            Archive("c3", "s", pages: 10),
            Archive("c4", "s", pages: 10),
        };
        var progress = new[] { Read("c1", completed: true), Read("c2", page: 5) };

        var s = One(nodes, progress, "s");

        s.Progress.Should().Be((1 + 0.5 + 0 + 0) / 4);
        s.IsCompleted.Should().BeFalse();
    }

    [Fact]
    public void Folder_Progress_IncludesNestedFolders()
    {
        var nodes = new[]
        {
            Folder("s"),
            Folder("v1", "s"),
            Archive("c1", "v1"),
            Folder("v2", "s"),
            Folder("v2a", "v2"),
            Archive("c2", "v2a"),
        };

        var s = One(nodes, [Read("c1", completed: true), Read("c2", completed: true)], "s");

        s.Progress.Should().Be(1);
        s.IsCompleted.Should().BeTrue();
    }

    [Fact]
    public void EmptyFolder_IsZeroAndNotCompleted()
    {
        var s = One([Folder("s")], [], "s");

        s.Progress.Should().Be(0);
        s.IsCompleted.Should().BeFalse();
    }

    // ── New chapters ──────────────────────────────────────────────────────

    [Fact]
    public void Folder_NeverOpened_HasNoNewCount()
    {
        var nodes = new[] { Folder("s"), Archive("c1", "s", addedDay: 0), Archive("c2", "s", addedDay: 9) };

        One(nodes, [], "s").NewCount.Should().Be(0);
    }

    [Fact]
    public void Folder_CountsChaptersAddedAfterLastRead()
    {
        var nodes = new[]
        {
            Folder("s"),
            Archive("c1", "s", addedDay: 0),
            Archive("c2", "s", addedDay: 0),
            Archive("c3", "s", addedDay: 6),
            Archive("c4", "s", addedDay: 7),
        };
        // Last read anything in the series on day 5.
        var progress = new[] { Read("c1", completed: true, readDay: 2), Read("c2", page: 3, readDay: 5) };

        var s = One(nodes, progress, "s");

        s.NewCount.Should().Be(2);
        s.IsCompleted.Should().BeFalse("new chapters make a finished series unfinished");
    }

    [Fact]
    public void Folder_ReadingANewChapter_ClearsOlderOnes()
    {
        // Reading c4 on day 8 moves the series' last read past c3's arrival.
        var nodes = new[]
        {
            Folder("s"),
            Archive("c1", "s", addedDay: 0),
            Archive("c3", "s", addedDay: 6),
            Archive("c4", "s", addedDay: 7),
        };
        var progress = new[] { Read("c1", completed: true, readDay: 5), Read("c4", page: 1, readDay: 8) };

        One(nodes, progress, "s").NewCount.Should().Be(0);
    }

    [Fact]
    public void Subfolder_NewCount_UsesTheWholeSeriesLastRead()
    {
        // Reading volume 1 on day 5 is what makes volume 2's later chapter new.
        var nodes = new[]
        {
            Folder("s"),
            Folder("v1", "s"),
            Archive("c1", "v1", addedDay: 0),
            Folder("v2", "s"),
            Archive("c2", "v2", addedDay: 0),
            Archive("c3", "v2", addedDay: 8),
        };

        var progress = new[] { Read("c1", page: 2, readDay: 5) };

        One(nodes, progress, "v2").NewCount.Should().Be(1);
        One(nodes, progress, "s").NewCount.Should().Be(1);
    }

    [Fact]
    public void Chapter_IsNew_WhenAddedAfterSeriesLastRead_AndUnopened()
    {
        var nodes = new[]
        {
            Folder("s"),
            Archive("c1", "s", addedDay: 0),
            Archive("c2", "s", addedDay: 6),
        };
        var summaries = ProgressSummaryService.Summarize(
            nodes,
            new[] { Read("c1", readDay: 5) }.ToDictionary(p => p.MediaId),
            ["c1", "c2"]);

        summaries.Single(s => s.MediaId == "c1").IsNew.Should().BeFalse();
        summaries.Single(s => s.MediaId == "c2").IsNew.Should().BeTrue();
    }

    [Fact]
    public void OtherSeries_DoNotAffectEachOther()
    {
        var nodes = new[]
        {
            Folder("a"), Archive("a1", "a", addedDay: 0),
            Folder("b"), Archive("b1", "b", addedDay: 0), Archive("b2", "b", addedDay: 3),
        };
        // Reading series A on day 9 says nothing about what is new in B.
        var progress = new[] { Read("a1", readDay: 9), Read("b1", readDay: 1) };

        One(nodes, progress, "b").NewCount.Should().Be(1);
    }

    // ── Request handling ──────────────────────────────────────────────────

    [Fact]
    public void UnknownAndDuplicateIds_AreHandled()
    {
        var summaries = ProgressSummaryService.Summarize(
            [Archive("a")], new Dictionary<string, ReadingProgress>(), ["a", "missing", "a"]);

        summaries.Select(s => s.MediaId).Should().Equal("a");
    }

    [Fact]
    public void LocalTimestamps_AreTreatedAsUtc()
    {
        // Rows come back from SQLite with Kind=Unspecified. They must compare
        // as UTC, not be shifted by the server's time zone.
        var nodes = new[]
        {
            Folder("s"),
            Archive("c1", "s"),
            new MediaNode("c2", "s", "archive", 10, DateTime.SpecifyKind(T0.AddHours(2), DateTimeKind.Unspecified)),
        };
        var progress = new ReadingProgress
        {
            MediaId = "c1",
            LastReadAt = DateTime.SpecifyKind(T0.AddHours(1), DateTimeKind.Unspecified),
        };

        One(nodes, [progress], "s").NewCount.Should().Be(1);
    }
}
