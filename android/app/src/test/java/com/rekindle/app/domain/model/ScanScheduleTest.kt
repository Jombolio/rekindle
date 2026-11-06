package com.rekindle.app.domain.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.Instant
import java.time.ZoneOffset

class ScanScheduleTest {

    private val utc = ZoneOffset.UTC
    private val now = Instant.parse("2026-11-06T09:00:00Z")

    @Test
    fun `times read as today, tomorrow, or a date`() {
        assertEquals("Today 18:00", ScanSchedule.timeLabel(Instant.parse("2026-11-06T18:00:00Z"), now, utc))
        assertEquals("Tomorrow 06:05", ScanSchedule.timeLabel(Instant.parse("2026-11-07T06:05:00Z"), now, utc))
        assertEquals("Fri 13 Nov 09:30", ScanSchedule.timeLabel(Instant.parse("2026-11-13T09:30:00Z"), now, utc))
    }

    @Test
    fun `server times with or without a zone are UTC`() {
        val expected = Instant.parse("2026-11-07T06:00:00Z")
        assertEquals(expected, ScanSchedule.parseTime("2026-11-07T06:00:00Z"))
        assertEquals(expected, ScanSchedule.parseTime("2026-11-07T06:00:00"))
        assertNull(ScanSchedule.parseTime(null))
        assertNull(ScanSchedule.parseTime("soon"))
    }

    @Test
    fun `intervals read plainly, including ones set elsewhere`() {
        assertEquals("Off", ScanSchedule.intervalLabel(0))
        assertEquals("Daily", ScanSchedule.intervalLabel(24))
        assertEquals("Every 3 hours", ScanSchedule.intervalLabel(3))
    }
}
