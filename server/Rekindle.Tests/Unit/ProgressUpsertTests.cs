using FluentAssertions;
using Rekindle.Core.Models;
using Xunit;
using Rekindle.Core.Repositories;
using Rekindle.Tests.Helpers;

namespace Rekindle.Tests.Unit;

public class ProgressUpsertTests : IDisposable
{
    private readonly TestDatabase _db = new();
    private readonly ProgressRepository _sut;
    private readonly UserRepository _users;
    private readonly LibraryRepository _libraries;
    private readonly MediaRepository _media;

    public ProgressUpsertTests()
    {
        _sut = new ProgressRepository(_db.Factory);
        _users = new UserRepository(_db.Factory);
        _libraries = new LibraryRepository(_db.Factory);
        _media = new MediaRepository(_db.Factory);
    }

    private async Task<(string UserId, string MediaId)> SeedAsync()
    {
        var userId = Guid.NewGuid().ToString();
        await _users.InsertAsync(new User { Id = userId, Username = "tester", PasswordHash = "x:y", PermissionLevel = 2 });

        var libId = Guid.NewGuid().ToString();
        await _libraries.InsertAsync(new Library { Id = libId, Name = "Comics", RootPath = "/tmp", Type = "comic" });

        var mediaId = Guid.NewGuid().ToString();
        await _media.InsertAsync(new Media
        {
            Id = mediaId, LibraryId = libId,
            Title = "Test Comic", FilePath = "/tmp/test.cbz", Format = "cbz"
        });

        return (userId, mediaId);
    }

    [Fact]
    public async Task Upsert_NewProgress_StoresCorrectly()
    {
        var (userId, mediaId) = await SeedAsync();

        await _sut.UpsertAsync(new ReadingProgress
        {
            UserId = userId, MediaId = mediaId, CurrentPage = 5,
            IsCompleted = false, LastReadAt = DateTime.UtcNow
        });

        var result = await _sut.GetAsync(userId, mediaId);
        result.Should().NotBeNull();
        result!.CurrentPage.Should().Be(5);
    }

    [Fact]
    public async Task Upsert_MaxPageWins_WhenIncomingPageIsHigher()
    {
        var (userId, mediaId) = await SeedAsync();
        var baseTime = DateTime.UtcNow;

        await _sut.UpsertAsync(new ReadingProgress
        {
            UserId = userId, MediaId = mediaId, CurrentPage = 10, LastReadAt = baseTime
        });
        await _sut.UpsertAsync(new ReadingProgress
        {
            UserId = userId, MediaId = mediaId, CurrentPage = 25, LastReadAt = baseTime.AddSeconds(1)
        });

        var result = await _sut.GetAsync(userId, mediaId);
        result!.CurrentPage.Should().Be(25);
    }

    [Fact]
    public async Task Upsert_MaxPageWins_DoesNotRollBackToLowerPage()
    {
        var (userId, mediaId) = await SeedAsync();
        var baseTime = DateTime.UtcNow;

        await _sut.UpsertAsync(new ReadingProgress
        {
            UserId = userId, MediaId = mediaId, CurrentPage = 50, LastReadAt = baseTime
        });
        await _sut.UpsertAsync(new ReadingProgress
        {
            UserId = userId, MediaId = mediaId, CurrentPage = 3, LastReadAt = baseTime.AddSeconds(1)
        });

        var result = await _sut.GetAsync(userId, mediaId);
        result!.CurrentPage.Should().Be(50);
    }

    [Fact]
    public async Task Upsert_ReReadAfterCompletion_ResetsToNewLowerPage()
    {
        var (userId, mediaId) = await SeedAsync();
        var baseTime = DateTime.UtcNow;

        // Finish the book.
        await _sut.UpsertAsync(new ReadingProgress
        {
            UserId = userId, MediaId = mediaId, CurrentPage = 100, IsCompleted = true, LastReadAt = baseTime
        });
        // Re-open (client restarts at 0) and read to page 5.
        await _sut.UpsertAsync(new ReadingProgress
        {
            UserId = userId, MediaId = mediaId, CurrentPage = 5, IsCompleted = false, LastReadAt = baseTime.AddSeconds(1)
        });

        var result = await _sut.GetAsync(userId, mediaId);
        // Un-completing must reset the resume position instead of clamping to 100.
        result!.CurrentPage.Should().Be(5);
        result.IsCompleted.Should().BeFalse();
    }

    [Fact]
    public async Task Upsert_IsCompleted_CanBeSetTrue()
    {
        var (userId, mediaId) = await SeedAsync();

        await _sut.UpsertAsync(new ReadingProgress
        {
            UserId = userId, MediaId = mediaId, CurrentPage = 200, IsCompleted = true,
            LastReadAt = DateTime.UtcNow
        });

        var result = await _sut.GetAsync(userId, mediaId);
        result!.IsCompleted.Should().BeTrue();
    }

    [Fact]
    public async Task GetAsync_NonExistentProgress_ReturnsNull()
    {
        var result = await _sut.GetAsync("no-user", "no-media");
        result.Should().BeNull();
    }

    // ── Trusted-ordering path (client-supplied timestamps) ────────────────────

    [Fact]
    public async Task Upsert_Trusted_BackwardNavigation_Persists()
    {
        var (userId, mediaId) = await SeedAsync();
        var baseTime = DateTime.UtcNow;

        await _sut.UpsertAsync(new ReadingProgress
        {
            UserId = userId, MediaId = mediaId, CurrentPage = 50, LastReadAt = baseTime
        }, trustClientOrdering: true);
        // The user paged back to re-read and closed at 30 — that IS the resume point.
        await _sut.UpsertAsync(new ReadingProgress
        {
            UserId = userId, MediaId = mediaId, CurrentPage = 30, LastReadAt = baseTime.AddSeconds(1)
        }, trustClientOrdering: true);

        var result = await _sut.GetAsync(userId, mediaId);
        result!.CurrentPage.Should().Be(30);
    }

    [Fact]
    public async Task Upsert_Trusted_StaleQueuedWrite_IsRejected()
    {
        var (userId, mediaId) = await SeedAsync();
        var baseTime = DateTime.UtcNow;

        await _sut.UpsertAsync(new ReadingProgress
        {
            UserId = userId, MediaId = mediaId, CurrentPage = 80, LastReadAt = baseTime
        }, trustClientOrdering: true);
        // An offline queue flushed from another device, carrying an OLDER write.
        await _sut.UpsertAsync(new ReadingProgress
        {
            UserId = userId, MediaId = mediaId, CurrentPage = 40, LastReadAt = baseTime.AddMinutes(-10)
        }, trustClientOrdering: true);

        var result = await _sut.GetAsync(userId, mediaId);
        result!.CurrentPage.Should().Be(80);
    }

    [Fact]
    public async Task Upsert_Trusted_StaleCompletedFlush_DoesNotResurrectCompletion()
    {
        var (userId, mediaId) = await SeedAsync();
        var baseTime = DateTime.UtcNow;

        // Device A finished the book, then the user started re-reading on device B.
        await _sut.UpsertAsync(new ReadingProgress
        {
            UserId = userId, MediaId = mediaId, CurrentPage = 40, IsCompleted = false, LastReadAt = baseTime
        }, trustClientOrdering: true);
        // Device A's stale offline queue arrives late with the old completion.
        await _sut.UpsertAsync(new ReadingProgress
        {
            UserId = userId, MediaId = mediaId, CurrentPage = 100, IsCompleted = true, LastReadAt = baseTime.AddMinutes(-5)
        }, trustClientOrdering: true);

        var result = await _sut.GetAsync(userId, mediaId);
        result!.IsCompleted.Should().BeFalse();
        result.CurrentPage.Should().Be(40);
    }

    [Fact]
    public async Task Upsert_Legacy_KeepsHighWaterMarkClamp()
    {
        var (userId, mediaId) = await SeedAsync();
        var baseTime = DateTime.UtcNow;

        // Writes without a client timestamp (older clients) keep the page-0-race guard.
        await _sut.UpsertAsync(new ReadingProgress
        {
            UserId = userId, MediaId = mediaId, CurrentPage = 50, LastReadAt = baseTime
        });
        await _sut.UpsertAsync(new ReadingProgress
        {
            UserId = userId, MediaId = mediaId, CurrentPage = 0, LastReadAt = baseTime.AddSeconds(1)
        });

        var result = await _sut.GetAsync(userId, mediaId);
        result!.CurrentPage.Should().Be(50);
    }

    public void Dispose() => _db.Dispose();
}
