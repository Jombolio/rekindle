package com.rekindle.app.core.update

/**
 * Counts taps towards turning something on that most people shouldn't: it takes
 * [required] taps, each within [windowMs] of the last. A slower tap starts the
 * count again.
 */
class TapToUnlock(private val required: Int = 3, private val windowMs: Long = 3000L) {

    private var taps = 0
    private var lastTapAt = Long.MIN_VALUE

    /** Taps still needed after the last one, or 0 once it unlocked. */
    var remaining: Int = required
        private set

    /** Records a tap at [nowMs]. True on the tap that unlocks, which also resets the count. */
    fun tap(nowMs: Long): Boolean {
        val inTime = lastTapAt != Long.MIN_VALUE && nowMs - lastTapAt <= windowMs
        taps = if (inTime) taps + 1 else 1
        lastTapAt = nowMs
        if (taps >= required) {
            reset()
            remaining = 0
            return true
        }
        remaining = required - taps
        return false
    }

    fun reset() {
        taps = 0
        lastTapAt = Long.MIN_VALUE
        remaining = required
    }
}
