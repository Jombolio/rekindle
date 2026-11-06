package com.rekindle.app.domain.model

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Locale

/** A library and how often the server scans it on its own. */
data class ScanSchedule(
    val libraryId: String,
    val libraryName: String,
    /** Hours between scheduled scans; 0 when there are none. */
    val intervalHours: Int,
    val lastRunAt: Instant?,
    val nextRunAt: Instant?,
) {
    companion object {
        /** The intervals offered, in hours, and how they read. 0 is off. */
        val INTERVALS: Map<Int, String> = linkedMapOf(
            0 to "Off",
            1 to "Every hour",
            6 to "Every 6 hours",
            12 to "Every 12 hours",
            24 to "Daily",
            168 to "Weekly",
        )

        fun intervalLabel(hours: Int): String = INTERVALS[hours] ?: "Every $hours hours"

        /** The server writes UTC; times without a zone are read as UTC. */
        fun parseTime(value: String?): Instant? = value?.let {
            runCatching { Instant.parse(if (it.endsWith("Z") || it.contains('+')) it else "${it}Z") }.getOrNull()
        }

        /** "Today 18:00", "Tomorrow 06:00", or "Fri 13 Nov 09:30", in [zone]. */
        fun timeLabel(at: Instant, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): String {
            val time: ZonedDateTime = at.atZone(zone)
            val today: LocalDate = now.atZone(zone).toLocalDate()
            val clock = time.format(DateTimeFormatter.ofPattern("HH:mm", Locale.UK))
            return when (ChronoUnit.DAYS.between(today, time.toLocalDate())) {
                0L -> "Today $clock"
                1L -> "Tomorrow $clock"
                -1L -> "Yesterday $clock"
                else -> time.format(DateTimeFormatter.ofPattern("EEE d MMM HH:mm", Locale.UK))
            }
        }
    }
}
