package com.gbsc.cherry.data

import kotlinx.serialization.Serializable

enum class Grade { GOOD, AVERAGE, BAD }

enum class CardPosition { LEFT, CENTER, RIGHT }

/** Color-grading thresholds the user sets in the Cherry Picker screen. */
@Serializable
data class Filters(
    val miBad: Double = 1.70,
    val miGood: Double = 2.10,
    val hrBad: Double = 47.0,
    val hrGood: Double = 57.0,
    val minBad: Double = 0.50,
    val minGood: Double = 0.80,
    val ratingBad: Double = 4.75,
    val ratingGood: Double = 4.90,
)

/** Inputs for the Net Profit Calculator (all monthly figures). */
@Serializable
data class ProfitConfig(
    val monthlyEarnings: Double = 5196.0,
    val monthlyMiles: Double = 3100.0,
    val monthlyHours: Double = 100.0,
    val financing: Double = 700.0,
    val fuel: Double = 312.0,
    val insurance: Double = 200.0,
    val maintenance: Double = 150.0,
    val phone: Double = 50.0,
    val other: Double = 75.0,
) {
    val totalCosts: Double get() = financing + fuel + insurance + maintenance + phone + other
    val netProfit: Double get() = monthlyEarnings - totalCosts
    val netMargin: Double get() = if (monthlyEarnings > 0) netProfit / monthlyEarnings * 100.0 else 0.0
    val earningsPerMile: Double get() = if (monthlyMiles > 0) monthlyEarnings / monthlyMiles else 0.0
    val earningsPerHour: Double get() = if (monthlyHours > 0) monthlyEarnings / monthlyHours else 0.0
    val costPerMile: Double get() = if (monthlyMiles > 0) totalCosts / monthlyMiles else 0.0
    val costPerHour: Double get() = if (monthlyHours > 0) totalCosts / monthlyHours else 0.0
}

@Serializable
data class Customization(
    val cardPosition: CardPosition = CardPosition.CENTER,
    val showPerMile: Boolean = true,
    val showPerHour: Boolean = true,
    val showPerMin: Boolean = false,
    val showRating: Boolean = true,
    val showTrip: Boolean = true,
    val showProfit: Boolean = true,
    val notificationEnabled: Boolean = true,
    val offsetY: Int = 120,
)

/** Everything persisted as a single settings blob. */
@Serializable
data class AppSettings(
    val filters: Filters = Filters(),
    val profit: ProfitConfig = ProfitConfig(),
    val customization: Customization = Customization(),
)

/** A single scanned trip offer, stored in history. */
@Serializable
data class TripOffer(
    val id: Long,
    val app: String = "Uber",
    val timestamp: Long,
    val fare: Double,
    val pickupMiles: Double = 0.0,
    val pickupMinutes: Double = 0.0,
    val tripMiles: Double = 0.0,
    val tripMinutes: Double = 0.0,
    val rating: Double? = null,
    val bonus: Double = 0.0,
    val pickupAddress: String? = null,
    val dropoffAddress: String? = null,
) {
    val totalMiles: Double get() = pickupMiles + tripMiles
    val totalMinutes: Double get() = pickupMinutes + tripMinutes
    val perMile: Double get() = if (totalMiles > 0) fare / totalMiles else 0.0
    val perHour: Double get() = if (totalMinutes > 0) fare / (totalMinutes / 60.0) else 0.0
    val perMin: Double get() = if (totalMinutes > 0) fare / totalMinutes else 0.0
}
