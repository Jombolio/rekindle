using System.Net;
using System.Net.Http.Json;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using Rekindle.Core.Repositories;
using Rekindle.Core.Services;
using Rekindle.Tests.Helpers;
using Xunit;

namespace Rekindle.Tests.Integration;

public class ScanScheduleEndpointTests : IClassFixture<TestWebApplicationFactory>
{
    private readonly HttpClient _client;
    private readonly TestWebApplicationFactory _factory;

    public ScanScheduleEndpointTests(TestWebApplicationFactory factory)
    {
        _factory = factory;
        _client = factory.CreateClient();
        _client.SetBearerToken(factory.AdminToken);
    }

    [Theory]
    [InlineData(1)]
    [InlineData(3)]
    public async Task Below_admin_cannot_see_or_set_schedules(int level)
    {
        var libraryId = await CreateLibraryAsync();
        var client = await ClientAtLevelAsync(level);

        (await client.GetAsync("/api/admin/scan-schedules")).StatusCode.Should().Be(HttpStatusCode.Forbidden);
        (await client.PutAsJsonAsync($"/api/admin/scan-schedules/{libraryId}", new { intervalHours = 6 }))
            .StatusCode.Should().Be(HttpStatusCode.Forbidden);
    }

    [Fact]
    public async Task Admin_sets_changes_and_clears_a_schedule()
    {
        var libraryId = await CreateLibraryAsync();

        var set = await _client.PutAsJsonAsync($"/api/admin/scan-schedules/{libraryId}", new { intervalHours = 6 });
        set.StatusCode.Should().Be(HttpStatusCode.OK);
        var body = await set.Content.ReadFromJsonAsync<ScheduleBody>();
        body!.IntervalHours.Should().Be(6);
        body.NextRunAt.Should().BeCloseTo(DateTime.UtcNow.AddHours(6), TimeSpan.FromMinutes(1));
        body.LastRunAt.Should().BeNull();

        var all = await _client.GetFromJsonAsync<List<ScheduleBody>>("/api/admin/scan-schedules");
        all!.Single(s => s.LibraryId == libraryId).IntervalHours.Should().Be(6);

        var weekly = await _client.PutAsJsonAsync($"/api/admin/scan-schedules/{libraryId}", new { intervalHours = 168 });
        (await weekly.Content.ReadFromJsonAsync<ScheduleBody>())!.NextRunAt
            .Should().BeCloseTo(DateTime.UtcNow.AddHours(168), TimeSpan.FromMinutes(1));

        var off = await _client.PutAsJsonAsync($"/api/admin/scan-schedules/{libraryId}", new { intervalHours = 0 });
        var cleared = await off.Content.ReadFromJsonAsync<ScheduleBody>();
        cleared!.IntervalHours.Should().Be(0);
        cleared.NextRunAt.Should().BeNull();
    }

    [Theory]
    [InlineData(-1)]
    [InlineData(721)]
    public async Task Rejects_intervals_out_of_range(int hours)
    {
        var libraryId = await CreateLibraryAsync();
        var resp = await _client.PutAsJsonAsync($"/api/admin/scan-schedules/{libraryId}", new { intervalHours = hours });
        resp.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Unknown_library_is_not_found()
    {
        var resp = await _client.PutAsJsonAsync("/api/admin/scan-schedules/nope", new { intervalHours = 6 });
        resp.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task Deleting_a_library_deletes_its_schedule()
    {
        var libraryId = await CreateLibraryAsync();
        await _client.PutAsJsonAsync($"/api/admin/scan-schedules/{libraryId}", new { intervalHours = 6 });

        (await _client.DeleteAsync($"/api/libraries/{libraryId}")).EnsureSuccessStatusCode();

        using var scope = _factory.Services.CreateScope();
        var schedules = scope.ServiceProvider.GetRequiredService<ScanScheduleRepository>();
        (await schedules.GetAsync(libraryId)).Should().BeNull();
    }

    [Fact]
    public async Task A_due_scan_runs_and_is_put_back_an_interval_later()
    {
        var libraryId = await CreateLibraryAsync();
        await _client.PutAsJsonAsync($"/api/admin/scan-schedules/{libraryId}", new { intervalHours = 12 });

        using var scope = _factory.Services.CreateScope();
        var schedules = scope.ServiceProvider.GetRequiredService<ScanScheduleRepository>();
        // Make it due now.
        await schedules.UpsertAsync(libraryId, 12, DateTime.UtcNow.AddMinutes(-1));

        var service = _factory.Services.GetRequiredService<ScheduledScanService>();
        var ran = await service.RunDueScansAsync();

        ran.Should().BeGreaterThanOrEqualTo(1);
        var after = await schedules.GetAsync(libraryId);
        after!.LastRunAt.Should().BeCloseTo(DateTime.UtcNow, TimeSpan.FromMinutes(1));
        after.NextRunAt.Should().BeCloseTo(DateTime.UtcNow.AddHours(12), TimeSpan.FromMinutes(1));
        _factory.Services.GetRequiredService<ScanProgressTracker>().Get(libraryId)!.Phase.Should().Be("complete");

        // Not due again straight away.
        (await service.RunDueScansAsync()).Should().Be(0);
    }

    [Fact]
    public async Task A_library_already_being_scanned_is_left_for_the_next_check()
    {
        var libraryId = await CreateLibraryAsync();
        await _client.PutAsJsonAsync($"/api/admin/scan-schedules/{libraryId}", new { intervalHours = 12 });
        using var scope = _factory.Services.CreateScope();
        var schedules = scope.ServiceProvider.GetRequiredService<ScanScheduleRepository>();
        await schedules.UpsertAsync(libraryId, 12, DateTime.UtcNow.AddMinutes(-1));

        var tracker = _factory.Services.GetRequiredService<ScanProgressTracker>();
        tracker.TryBeginScan(libraryId).Should().BeTrue();
        try
        {
            await _factory.Services.GetRequiredService<ScheduledScanService>().RunDueScansAsync();
            (await schedules.GetAsync(libraryId))!.LastRunAt.Should().BeNull();
        }
        finally
        {
            tracker.ReleaseScan(libraryId);
        }
    }

    private async Task<string> CreateLibraryAsync()
    {
        var root = Path.Combine(Path.GetTempPath(), $"rekindle-sched-{Guid.NewGuid():N}");
        Directory.CreateDirectory(root);
        var resp = await _client.PostAsJsonAsync("/api/libraries", new { name = $"Lib {Guid.NewGuid():N}", rootPath = root, type = "comic" });
        resp.EnsureSuccessStatusCode();
        return (await resp.Content.ReadFromJsonAsync<IdBody>())!.Id;
    }

    private async Task<HttpClient> ClientAtLevelAsync(int level)
    {
        var username = $"user{Guid.NewGuid():N}";
        const string password = "Password123!";
        (await _client.PostAsJsonAsync("/api/users", new { username, password, permissionLevel = level }))
            .EnsureSuccessStatusCode();
        var client = _factory.CreateClient();
        client.SetBearerToken(await AuthHelper.LoginAsync(client, username, password));
        return client;
    }

    private record IdBody(string Id);

    private record ScheduleBody(string LibraryId, string LibraryName, int IntervalHours, DateTime? LastRunAt, DateTime? NextRunAt);
}
