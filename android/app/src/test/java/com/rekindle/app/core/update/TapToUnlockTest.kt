package com.rekindle.app.core.update

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TapToUnlockTest {

    @Test
    fun `three quick taps unlock, counting down on the way`() {
        val unlock = TapToUnlock(required = 3, windowMs = 3000)
        assertFalse(unlock.tap(0))
        assertEquals(2, unlock.remaining)
        assertFalse(unlock.tap(1000))
        assertEquals(1, unlock.remaining)
        assertTrue(unlock.tap(2000))
        assertEquals(0, unlock.remaining)
    }

    @Test
    fun `a slow tap starts the count again`() {
        val unlock = TapToUnlock(required = 3, windowMs = 3000)
        unlock.tap(0)
        unlock.tap(1000)
        assertFalse(unlock.tap(5000))
        assertEquals(2, unlock.remaining)
        assertFalse(unlock.tap(6000))
        assertTrue(unlock.tap(7000))
    }

    @Test
    fun `after unlocking, it takes three taps again`() {
        val unlock = TapToUnlock(required = 3, windowMs = 3000)
        repeat(3) { unlock.tap(it * 100L) }
        assertFalse(unlock.tap(400))
        assertFalse(unlock.tap(500))
        assertTrue(unlock.tap(600))
    }
}
