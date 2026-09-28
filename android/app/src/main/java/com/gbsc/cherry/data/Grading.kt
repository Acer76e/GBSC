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

    fun color(grade: Grade, colorblind: Boolean = false): Int =
        if (colorblind) when (grade) {
            Grade.GOOD -> 0xFF0072B2.toInt()    // blue
            Grade.AVERAGE -> 0xFFF0E442.toInt() // yellow
            Grade.BAD -> 0xFFD55E00.toInt()     // vermillion
        } else when (grade) {
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

    private fun score(g: Grade): Int = when (g) {
        Grade.GOOD -> 2
        Grade.AVERAGE -> 1
        Grade.BAD -> 0
    }

    /** Single "is it worth it" grade, averaged across the supplied per-stat grades. */
    fun averageGrade(grades: List<Grade>): Grade {
        if (grades.isEmpty()) return Grade.AVERAGE
        val avg = grades.sumOf { score(it) }.toDouble() / grades.size
        return when {
            avg >= 1.5 -> Grade.GOOD
            avg >= 0.75 -> Grade.AVERAGE
            else -> Grade.BAD
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
