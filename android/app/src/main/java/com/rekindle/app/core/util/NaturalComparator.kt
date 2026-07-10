package com.rekindle.app.core.util

/** Compares strings with embedded numbers in natural order ("Chapter 2" before "Chapter 10"). */
object NaturalComparator : Comparator<String> {
    private val chunk = Regex("""\d+|\D+""")
    override fun compare(a: String, b: String): Int {
        val ac = chunk.findAll(a).map { it.value }.toList()
        val bc = chunk.findAll(b).map { it.value }.toList()
        for (i in 0 until minOf(ac.size, bc.size)) {
            val x = ac[i]
            val y = bc[i]
            val cmp = if (x[0].isDigit() && y[0].isDigit()) {
                (x.toLongOrNull() ?: Long.MAX_VALUE).compareTo(y.toLongOrNull() ?: Long.MAX_VALUE)
            } else {
                x.compareTo(y, ignoreCase = true)
            }
            if (cmp != 0) return cmp
        }
        return ac.size - bc.size
    }
}
