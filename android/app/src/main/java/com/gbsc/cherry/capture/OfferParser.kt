package com.gbsc.cherry.capture

/**
 * Best-effort parser that turns OCR text from an Uber Driver offer card into structured fields.
 *
 * Uber offer cards (US) look roughly like:
 *   $36.24
 *   ★ 4.79   +$18.00 included
 *   8 mins (1.4 mi) away
 *   N Menard Ave & W Jarvis Ave, Niles
 *   37 mins (7.6 mi) trip
 *   N Leavitt St & W Wilson Ave, Chicago
 *   Accept
 *
 * These heuristics are intentionally tolerant; they will need tuning against the live Uber
 * layout on the user's device.
 */
object OfferParser {

    data class ParsedOffer(
        val fare: Double,
        val bonus: Double,
        val pickupMinutes: Double,
        val pickupMiles: Double,
        val tripMinutes: Double,
        val tripMiles: Double,
        val rating: Double?,
        val pickupAddress: String?,
        val dropoffAddress: String?,
    )

    private val moneyRegex = Regex("""\$\s*(\d{1,4})[.,](\d{2})""")
    private val bonusRegex = Regex("""\+\s*\$?\s*(\d{1,3})(?:[.,](\d{2}))?""")
    private val pairRegex = Regex("""(\d{1,3})\s*min[s]?\b[^0-9]{0,20}?(\d{1,3}(?:[.,]\d{1,2})?)\s*mi\b""", RegexOption.IGNORE_CASE)
    private val rateAfterRegex = Regex("""^\s*(/|\s)?\s*(active\s+)?(hr|hour|h|min|minute|per\s+(hour|min))\b""", RegexOption.IGNORE_CASE)
    private val ratingStar = Regex("""[★⭐]\s*(\d)[.,](\d{1,2})""")
    private val ratingWord = Regex("""rating[^0-9]{0,8}(\d)[.,](\d{1,2})""", RegexOption.IGNORE_CASE)
    private val bareRating = Regex("""^[★⭐]?\s*(\d)[.,](\d{2})$""")
    private val streetSuffix = Regex(
        """\b(Ave|St|Blvd|Rd|Dr|Ln|Way|Hwy|Ct|Pkwy|Pl|Ter|Cir|Sq|Trail|Trl|Airport|Station)\b""",
        RegexOption.IGNORE_CASE
    )

    private fun num(intPart: String, decPart: String): Double =
        "$intPart.$decPart".toDoubleOrNull() ?: 0.0

    private fun dec(raw: String): Double = raw.replace(',', '.').toDoubleOrNull() ?: 0.0

    private val acceptOrMatchRegex = Regex("""\b(accept|match)\b""", RegexOption.IGNORE_CASE)

    fun parse(text: String): ParsedOffer? {
        if (text.isBlank()) return null
        // An offer card always has either an "Accept" or a "Match" button. In-trip
        // navigation, earnings, and other Uber screens contain $ amounts and min/mi
        // pairs too — without this gate the parser would treat them all as new offers.
        if (!acceptOrMatchRegex.containsMatchIn(text)) return null
        val lines = text.lines().map { it.trim() }.filter { it.isNotEmpty() }

        // --- Bonus first, so we can exclude bonus amounts from the fare detection ---
        var bonus = 0.0
        for (m in bonusRegex.findAll(text)) {
            val v = num(m.groupValues[1], m.groupValues[2].ifEmpty { "00" })
            if (v > bonus) bonus = v
        }

        // --- Fare: largest dollar amount that isn't a bonus (preceded by '+') or a rate
        // estimate (followed by "/hr", "active hr", "per hour", "/min", etc.).
        var fare = 0.0
        for (m in moneyRegex.findAll(text)) {
            val before = text.substring(0, m.range.first).trimEnd()
            if (before.endsWith("+")) continue
            val after = text.substring(m.range.last + 1).take(30)
            if (rateAfterRegex.containsMatchIn(after)) continue
            val v = num(m.groupValues[1], m.groupValues[2])
            if (v > fare) fare = v
        }
        if (fare <= 0.0) return null

        // --- min/mi pairs (pickup then trip in card order) ---
        val pairs = pairRegex.findAll(text).map {
            Pair(it.groupValues[1].toDoubleOrNull() ?: 0.0, dec(it.groupValues[2]))
        }.toList()
        if (pairs.isEmpty()) return null

        val pickupMinutes: Double
        val pickupMiles: Double
        val tripMinutes: Double
        val tripMiles: Double
        if (pairs.size >= 2) {
            pickupMinutes = pairs[0].first; pickupMiles = pairs[0].second
            tripMinutes = pairs[1].first; tripMiles = pairs[1].second
        } else {
            pickupMinutes = 0.0; pickupMiles = 0.0
            tripMinutes = pairs[0].first; tripMiles = pairs[0].second
        }
        if ((pickupMiles + tripMiles) <= 0.0 || (pickupMinutes + tripMinutes) <= 0.0) return null

        // --- Rating ---
        val rating: Double? = run {
            ratingStar.find(text)?.let { return@run num(it.groupValues[1], it.groupValues[2]) }
            ratingWord.find(text)?.let { return@run num(it.groupValues[1], it.groupValues[2]) }
            for (l in lines) {
                val m = bareRating.find(l) ?: continue
                val v = num(m.groupValues[1], m.groupValues[2])
                if (v in 3.5..5.0) return@run v
            }
            null
        }

        // --- Addresses ---
        val addressLines = lines.filter { l ->
            val lower = l.lowercase()
            val looksLikeNoise = lower.contains("min") || lower.contains(" mi") ||
                l.contains("$") || lower.contains("accept") || lower.contains("away") ||
                lower.contains("trip") || lower.contains("bonus") || lower.contains("incl") ||
                l.contains("%")
            !looksLikeNoise && (l.contains("&") || streetSuffix.containsMatchIn(l) ||
                Regex("""^\d+\s+\S""").containsMatchIn(l))
        }
        val pickupAddress = addressLines.getOrNull(0)
        val dropoffAddress = addressLines.getOrNull(1) ?: addressLines.lastOrNull()?.takeIf { it != pickupAddress }

        return ParsedOffer(
            fare = fare,
            bonus = bonus,
            pickupMinutes = pickupMinutes,
            pickupMiles = pickupMiles,
            tripMinutes = tripMinutes,
            tripMiles = tripMiles,
            rating = rating,
            pickupAddress = pickupAddress,
            dropoffAddress = dropoffAddress,
        )
    }
}
