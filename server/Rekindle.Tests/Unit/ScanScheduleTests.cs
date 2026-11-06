using FluentAssertions;
using Rekindle.Core.Models;
using Xunit;

namespace Rekindle.Tests.Unit;

public class ScanScheduleTests
{
    private static readonly DateTime Noon = new(2026, 11, 6, 12, 0, 0, DateTimeKind.Utc);

    [Fact]
    public void Next_scan_keeps_the_rhythm_from_when_the_last_one_started()
    {
        var next = ScanSchedule.NextAfter(Noon, Noon.AddMinutes(10), intervalHours: 6);
        next.Should().Be(Noon.AddHours(6));
    }

    [Fact]
    public void A_scan_longer_than_its_interval_waits_a_full_interval_from_its_end()
    {
        var finished = Noon.AddHours(2);
        var next = ScanSchedule.NextAfter(Noon, finished, intervalHours: 1);
        next.Should().Be(finished.AddHours(1));
    }

    [Fact]
    public void A_new_schedule_first_runs_one_interval_from_now()
    {
        ScanSchedule.FirstDue(lastRunUtc: null, Noon, intervalHours: 24).Should().Be(Noon.AddHours(24));
    }

    [Fact]
    public void A_changed_interval_counts_from_the_last_scheduled_scan()
    {
        ScanSchedule.FirstDue(Noon.AddHours(-2), Noon, intervalHours: 6).Should().Be(Noon.AddHours(4));
    }

    [Fact]
    public void A_changed_interval_already_overdue_runs_now_rather_than_in_the_past()
    {
        ScanSchedule.FirstDue(Noon.AddHours(-30), Noon, intervalHours: 24).Should().Be(Noon);
    }

    [Fact]
    public void Due_once_its_time_has_come()
    {
        var schedule = new ScanSchedule { NextRunAt = Noon };
        schedule.IsDue(Noon.AddSeconds(-1)).Should().BeFalse();
        schedule.IsDue(Noon).Should().BeTrue();
    }
}
