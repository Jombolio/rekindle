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

    public void Dispose() => _db.Dispose();
}
