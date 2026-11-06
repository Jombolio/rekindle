package com.rekindle.app.domain.model

import com.rekindle.app.data.model.ProgressSummaryDto
import com.rekindle.app.data.model.toDomain
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ProgressSummaryTest {

    @Test
    fun fromLocal_usesPageCountWhenKnown() {
        val s = ProgressSummary.fromLocal("m", currentPage = 10, isCompleted = false, pageCount = 40)

        assertEquals(0.25f, s.progress, 0f)
        assertEquals(25, s.percent)
        assertTrue(s.isStarted)
    }

    @Test
    fun fromLocal_completedIsFullWithoutPageCount() {
        val s = ProgressSummary.fromLocal("m", currentPage = 2, isCompleted = true, pageCount = null)

        assertEquals(1f, s.progress, 0f)
        assertTrue(s.isCompleted)
    }

    @Test
    fun fromLocal_unknownPageCountGivesNoFraction() {
        val s = ProgressSummary.fromLocal("m", currentPage = 10, isCompleted = false, pageCount = null)

        assertEquals(0f, s.progress, 0f)
        assertFalse(s.isStarted)
    }

    @Test
    fun fromLocal_clampsPagesBeyondCount() {
        val s = ProgressSummary.fromLocal("m", currentPage = 50, isCompleted = false, pageCount = 10)

        assertEquals(1f, s.progress, 0f)
    }

    @Test
    fun dto_mapsEveryFieldAndClampsProgress() {
        val s = ProgressSummaryDto("a", progress = 1.4, isCompleted = false, newCount = 3, isNew = true).toDomain()

        assertEquals("a", s.mediaId)
        assertEquals(1f, s.progress, 0f)
        assertEquals(3, s.newCount)
        assertTrue(s.isNew)
    }

    @Test
    fun unstartedSummary_isNotStarted() {
        assertFalse(ProgressSummary("a", progress = 0f, isCompleted = false).isStarted)
    }

    @Test
    fun `a read mark comes through, and older servers mean none`() {
        val marked = ProgressSummaryDto(mediaId = "a", progress = 1.0, isCompleted = true, markedRead = true).toDomain()
        assertTrue(marked.markedRead)
        assertTrue(marked.isCompleted)
        assertFalse(ProgressSummaryDto(mediaId = "b").toDomain().markedRead)
    }

    @Test
    fun `an ignored archive comes through, and older servers mean tracked`() {
        assertTrue(ProgressSummaryDto(mediaId = "a", ignored = true).toDomain().ignored)
        assertFalse(ProgressSummaryDto(mediaId = "b").toDomain().ignored)
    }
}
