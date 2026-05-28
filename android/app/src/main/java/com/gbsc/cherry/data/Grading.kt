package com.gbsc.cherry.data

import android.graphics.Color

object Grading {

    /** Higher-is-better grading (used for $/mi, $/hr, $/min, rating). */
    fun grade(value: Double, bad: Double, good: Double): Grade {
        val lo = minOf(bad, good)
        val hi = maxOf(bad, good)
        return when {
            value >= hi -> Grade.GOOD
            value <= lo -> Grade.BAD
            else -> Grade.AVERAGE
        }
    }

    fun color(grade: Grade): Int = when (grade) {
        Grade.GOOD -> 0xFF22C55E.toInt()
        Grade.AVERAGE -> 0xFFF5C518.toInt()
        Grade.BAD -> 0xFFEF4444.toInt()
    }

    /** Overall grade for an offer: worst of the per-mile and per-hour grades. */
    fun overall(offer: TripOffer, f: Filters): Grade {
        val gMi = grade(offer.perMile, f.miBad, f.miGood)
        val gHr = grade(offer.perHour, f.hrBad, f.hrGood)
        val grades = listOf(gMi, gHr)
        return when {
            grades.any { it == Grade.BAD } -> Grade.BAD
            grades.any { it == Grade.AVERAGE } -> Grade.AVERAGE
            else -> Grade.GOOD
        }
    }

    fun colorHex(grade: Grade): String = when (grade) {
        Grade.GOOD -> "#22C55E"
        Grade.AVERAGE -> "#F5C518"
        Grade.BAD -> "#EF4444"
    }

    @Suppress("unused")
    fun parseColor(hex: String): Int = Color.parseColor(hex)
}
