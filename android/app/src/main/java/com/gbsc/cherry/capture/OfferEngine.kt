package com.gbsc.cherry.capture

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.speech.tts.TextToSpeech
import androidx.core.app.NotificationCompat
import com.gbsc.cherry.MainActivity
import com.gbsc.cherry.R
import com.gbsc.cherry.data.AppSettings
import com.gbsc.cherry.data.CardTheme
import com.gbsc.cherry.data.Grade
import com.gbsc.cherry.data.Grading
import com.gbsc.cherry.data.Repo
import com.gbsc.cherry.data.TripOffer
import com.gbsc.cherry.overlay.OverlayController
import com.gbsc.cherry.overlay.OverlayData
import kotlinx.coroutines.flow.MutableStateFlow
import java.util.Locale

/**
 * Single offer-processing pipeline used by the accessibility service. Initialised lazily
 * and lives for the process lifetime — Android cleans up when the process exits.
 */
object OfferEngine {

    const val CHANNEL_OFFER = "offer"
    const val NOTIF_OFFER = 2

    /** True when the user has tapped "Start" in the app. */
    val scanning = MutableStateFlow(false)
    /** True while the AccessibilityService is connected. */
    val accessibilityConnected = MutableStateFlow(false)

    /** Snapshot of the most recent accessibility event for the in-app diagnostic panel. */
    data class DebugSnapshot(
        val timestamp: Long,
        val pkg: String?,
        val textChars: Int,
        val textPreview: String,
        val parsed: Boolean,
        val fare: Double,
        val nodeCount: Int = 0,
        val classes: String = "",
        val windowsSummary: String = "",
    )
    val lastDebug = MutableStateFlow<DebugSnapshot?>(null)
    /** Last Uber screen that looked like an offer card (contained "Accept" or "Match").
     *  Preserved across non-offer screens so the user can verify what we captured. */
    val lastOfferDebug = MutableStateFlow<DebugSnapshot?>(null)
    /** Highest-node Uber capture we've ever taken — preserves the offer card after it
     *  closes so we can verify what the tree looked like at peak content. */
    val biggestUberDebug = MutableStateFlow<DebugSnapshot?>(null)
    /** Last 5 Uber captures (any size) so the user can scroll back to find what was on
     *  screen during a recent offer, even if it didn't beat the biggest. */
    val recentUberCaptures = MutableStateFlow<List<DebugSnapshot>>(emptyList())
    /** Most recent foreground package seen in debug mode that isn't an Uber window. */
    val lastSeenPkg = MutableStateFlow<String?>(null)
    /** Recent distinct package names seen, most-recent-first, capped at 10. */
    val recentPackages = MutableStateFlow<List<String>>(emptyList())
    /** Number of polling re-reads since the service started. */
    val pollCount = MutableStateFlow(0)
    /** Number of OCR fallbacks performed (when Uber hides the offer card from accessibility). */
    val ocrCount = MutableStateFlow(0)
    /** Preview of the last OCR result for diagnostic visibility. */
    val lastOcrPreview = MutableStateFlow<String?>(null)

    private val offerKeywordRegex = Regex("""\b(accept|match)\b""", RegexOption.IGNORE_CASE)
    private val fareRegex = Regex("""\$\s*\d{1,4}[.,]\d{2}""")
    private val minRegex = Regex("""\d{1,3}\s*min[s]?\b""", RegexOption.IGNORE_CASE)

    fun looksLikeOffer(text: String): Boolean =
        offerKeywordRegex.containsMatchIn(text) &&
            fareRegex.containsMatchIn(text) &&
            minRegex.containsMatchIn(text)

    fun recordOcrText(text: String) {
        lastOcrPreview.value = text.take(200).replace('\n', ' ')
        ocrCount.value = ocrCount.value + 1
    }

    fun recordDebug(
        pkg: String?,
        text: String,
        nodeCount: Int = 0,
        classes: String = "",
        windowsSummary: String = "",
        isUber: Boolean = false,
    ) {
        val snapshot = DebugSnapshot(
            timestamp = System.currentTimeMillis(),
            pkg = pkg,
            textChars = text.length,
            textPreview = text.take(200).replace('\n', ' '),
            parsed = false,
            fare = 0.0,
            nodeCount = nodeCount,
            classes = classes,
            windowsSummary = windowsSummary,
        )
        lastDebug.value = snapshot
        if (looksLikeOffer(text)) {
            lastOfferDebug.value = snapshot
        }
        if (isUber) {
            val biggest = biggestUberDebug.value
            if (biggest == null || nodeCount > biggest.nodeCount) {
                biggestUberDebug.value = snapshot
            }
            // Push to the rolling 10-deep list, deduping consecutive captures with the
            // same preview so a static dashboard doesn't fill all the slots.
            if (text.isNotBlank()) {
                val list = recentUberCaptures.value.toMutableList()
                if (list.firstOrNull()?.textPreview != snapshot.textPreview) {
                    list.add(0, snapshot)
                    while (list.size > 10) list.removeAt(list.size - 1)
                    recentUberCaptures.value = list
                }
            }
        }
        if (pkg != null) addRecent(pkg)
    }

    fun recordSeenPkg(pkg: String?) {
        if (pkg == null) return
        lastSeenPkg.value = pkg
        addRecent(pkg)
    }

    @Synchronized
    private fun addRecent(pkg: String) {
        val current = recentPackages.value
        val updated = (listOf(pkg) + current.filterNot { it == pkg }).take(10)
        if (updated != current) recentPackages.value = updated
    }

    private const val MISS_LIMIT = 3

    private var appContext: Context? = null
    private var overlay: OverlayController? = null
    private var tts: TextToSpeech? = null
    private var ttsReady = false

    /** Stable overlay identity for the offer currently on screen (includes a timestamp
     *  so two logical offers can never share a signature). */
    private var currentSignature: String? = null
    /** Structured record of the offer currently on screen. Same-offer detection is
     *  tolerance-based (OCR wobbles cents and decimals frame to frame), and each new
     *  parse fills in null fields from this record so noise doesn't flicker the
     *  rating/addresses/bonus on the card. */
    private var currentOffer: TripOffer? = null
    /** When the current offer was last seen; same-offer matching is time-bounded. */
    private var currentOfferSeenAt = 0L
    private var missCount = 0
    /** Consecutive non-offer Uber frames reported by the service (see [onNoOffer]). */
    private var noOfferFrames = 0
    private const val NO_OFFER_DEBOUNCE = 2

    // Conservative same-offer tolerances: only treat two parses as the SAME offer when
    // fare AND miles AND minutes are all close and the previous sighting is recent.
    // Distinct back-to-back offers almost always differ well beyond these bounds.
    private const val SAME_FARE_TOLERANCE = 0.25
    private const val SAME_MILES_TOLERANCE = 0.3
    private const val SAME_MINUTES_TOLERANCE = 1.0
    private const val SAME_OFFER_WINDOW_MS = 90_000L

    private fun isSameOffer(current: TripOffer, fresh: TripOffer, now: Long): Boolean =
        now - currentOfferSeenAt <= SAME_OFFER_WINDOW_MS &&
            kotlin.math.abs(fresh.fare - current.fare) <= SAME_FARE_TOLERANCE &&
            kotlin.math.abs(fresh.totalMiles - current.totalMiles) <= SAME_MILES_TOLERANCE &&
            kotlin.math.abs(fresh.totalMinutes - current.totalMinutes) <= SAME_MINUTES_TOLERANCE

    fun ensureInit(context: Context) {
        if (appContext != null) return
        appContext = context.applicationContext
        ensureChannels(context.applicationContext)
        overlay = OverlayController(context.applicationContext)
        tts = TextToSpeech(context.applicationContext) { status ->
            if (status == TextToSpeech.SUCCESS) {
                tts?.language = Locale.US
                ttsReady = true
            }
        }
    }

    /** Process a frame of text (from accessibility nodes or OCR). Returns true on a brand-new offer. */
    fun processText(text: String): Boolean {
        if (!scanning.value) return false
        val ctx = appContext ?: return false
        val parsed = OfferParser.parse(text)
        if (parsed == null) {
            lastDebug.value = lastDebug.value?.copy(parsed = false)
            lastOfferDebug.value = lastOfferDebug.value?.copy(parsed = false)
            missCount++
            if (missCount >= MISS_LIMIT) {
                currentSignature = null
                currentOffer = null
                overlay?.hide()
                notificationManager(ctx).cancel(NOTIF_OFFER)
            }
            return false
        }
        lastDebug.value = lastDebug.value?.copy(parsed = true, fare = parsed.fare)
        lastOfferDebug.value = lastOfferDebug.value?.copy(parsed = true, fare = parsed.fare)
        missCount = 0
        noOfferFrames = 0
        val freshOffer = TripOffer(
            id = System.currentTimeMillis(),
            timestamp = System.currentTimeMillis(),
            fare = parsed.fare,
            bonus = parsed.bonus,
            pickupMiles = parsed.pickupMiles,
            pickupMinutes = parsed.pickupMinutes,
            tripMiles = parsed.tripMiles,
            tripMinutes = parsed.tripMinutes,
            rating = parsed.rating,
            pickupAddress = parsed.pickupAddress,
            dropoffAddress = parsed.dropoffAddress,
        )
        val now = System.currentTimeMillis()
        // OCR is noisy: a one-cent fare wobble or a 0.1mi jitter must not count as a
        // brand-new offer (duplicate history row, re-notify, TTS over itself). Compare
        // against the current offer with tolerances instead of an exact string, and if
        // it's the same offer, hold onto fields we've already detected so partial-read
        // frames don't flicker the rating, addresses, or bonus on the card.
        val cached = currentOffer
        val isNew = cached == null || currentSignature == null || !isSameOffer(cached, freshOffer, now)
        val offer = if (!isNew && cached != null) {
            freshOffer.copy(
                rating = freshOffer.rating ?: cached.rating,
                pickupAddress = freshOffer.pickupAddress ?: cached.pickupAddress,
                dropoffAddress = freshOffer.dropoffAddress ?: cached.dropoffAddress,
                bonus = maxOf(freshOffer.bonus, cached.bonus),
            )
        } else {
            freshOffer
        }
        currentOffer = offer
        currentOfferSeenAt = now

        val signature: String
        if (isNew) {
            signature = String.format(
                Locale.US, "%.2f|%.1f|%.0f|%d",
                offer.fare, offer.totalMiles, offer.totalMinutes, now
            )
            currentSignature = signature
        } else {
            signature = currentSignature ?: return false // never null when !isNew
        }

        val settings = Repo.settings.value
        // A brand-new offer must never be suppressed by the dismissal of a previous
        // identical-signature offer (auto-hide timer or the X button).
        if (isNew) overlay?.clearDismissed()
        overlay?.show(buildOverlayData(offer, settings, signature))

        if (isNew) {
            Repo.addOffer(offer)
            if (settings.customization.notificationEnabled) postOfferNotification(ctx, offer, settings)
            if (settings.customization.voiceEnabled) speakOffer(offer, settings)
            return true
        }
        return false
    }

    fun resetState() {
        currentSignature = null
        currentOffer = null
        currentOfferSeenAt = 0L
        missCount = 0
        noOfferFrames = 0
        overlay?.clearDismissed()
        overlay?.hide()
        appContext?.let { notificationManager(it).cancel(NOTIF_OFFER) }
    }

    /** Called by the accessibility service when Uber is on screen but the current frame
     *  is not offer-shaped (e.g. the dashboard after an offer expires). Debounced over
     *  [NO_OFFER_DEBOUNCE] consecutive frames so a single dropped/partial frame in the
     *  middle of an offer doesn't flap the card, then hides the overlay and cancels the
     *  offer notification. */
    fun onNoOffer() {
        if (currentSignature == null && currentOffer == null) {
            noOfferFrames = 0
            return
        }
        noOfferFrames++
        if (noOfferFrames < NO_OFFER_DEBOUNCE) return
        noOfferFrames = 0
        currentSignature = null
        currentOffer = null
        currentOfferSeenAt = 0L
        missCount = 0
        overlay?.hide()
        appContext?.let { notificationManager(it).cancel(NOTIF_OFFER) }
    }

    /** Pushes a synthetic offer through the full pipeline so the user can verify the card,
     *  notification, and voice without going online in Uber. */
    fun showTestOffer() {
        val ctx = appContext ?: return
        val offer = TripOffer(
            id = System.currentTimeMillis(),
            timestamp = System.currentTimeMillis(),
            fare = 36.24,
            bonus = 18.00,
            pickupMiles = 1.4,
            pickupMinutes = 8.0,
            tripMiles = 7.6,
            tripMinutes = 37.0,
            rating = 4.79,
            pickupAddress = "N Menard Ave & W Jarvis Ave, Niles",
            dropoffAddress = "N Leavitt St & W Wilson Ave, Chicago",
        )
        val signature = "test-" + System.currentTimeMillis()
        val settings = Repo.settings.value
        overlay?.show(buildOverlayData(offer, settings, signature))
        Repo.addOffer(offer)
        if (settings.customization.notificationEnabled) postOfferNotification(ctx, offer, settings)
        if (settings.customization.voiceEnabled) speakOffer(offer, settings)
    }

    fun saveScreenshot(bmp: Bitmap) {
        val ctx = appContext ?: return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        val name = "cherrypick_" + System.currentTimeMillis() + ".jpg"
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, name)
            put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
            put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/CherryPick")
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val resolver = ctx.contentResolver
        val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values) ?: return
        resolver.openOutputStream(uri)?.use { out ->
            bmp.compress(Bitmap.CompressFormat.JPEG, 90, out)
        }
        values.clear()
        values.put(MediaStore.Images.Media.IS_PENDING, 0)
        resolver.update(uri, values, null, null)
    }

    // ---- builders ----

    private fun buildOverlayData(offer: TripOffer, settings: AppSettings, signature: String): OverlayData {
        val f = settings.filters
        val c = settings.customization
        val cb = c.colorblind
        val miGrade = Grading.grade(offer.perMile, f.miBad, f.miGood)
        val hrGrade = Grading.grade(offer.perHour, f.hrBad, f.hrGood)
        val minGrade = Grading.grade(offer.perMin, f.minBad, f.minGood)
        val ratingGrade = offer.rating?.let { Grading.grade(it, f.ratingBad, f.ratingGood) } ?: Grade.AVERAGE

        val profit = offer.fare - settings.profit.costPerMile * offer.totalMiles
        val profitPct = if (offer.fare > 0) (profit / offer.fare * 100).toInt() else 0
        val profitPerHour = if (offer.totalMinutes > 0) profit / (offer.totalMinutes / 60.0) else 0.0
        val profitGood = profit >= 0

        val profitParts = buildList {
            if (c.showProfit) add("$" + fmt2(profit))
            if (c.showProfitPct) add("$profitPct%")
            if (c.showProfitPerHour) add("$" + fmt2(profitPerHour) + "/hr")
        }
        val profitText = if (profitParts.isEmpty()) null else "Profit: " + profitParts.joinToString("  ")

        val shownGrades = buildList {
            if (c.showPerMile) add(miGrade)
            if (c.showPerHour) add(hrGrade)
            if (c.showPerMin) add(minGrade)
            if (c.showRating && offer.rating != null) add(ratingGrade)
        }
        val borderGrade =
            if (shownGrades.isEmpty()) Grading.overall(offer, f) else Grading.averageGrade(shownGrades)

        val theme = themeColors(c.cardTheme)

        return OverlayData(
            signature = signature,
            fareText = "$" + fmt2(offer.fare),
            miValue = fmt2(offer.perMile),
            miColor = Grading.color(miGrade, cb),
            showMi = c.showPerMile,
            hrValue = fmt2(offer.perHour),
            hrColor = Grading.color(hrGrade, cb),
            showHr = c.showPerHour,
            minValue = fmt2(offer.perMin),
            minColor = Grading.color(minGrade, cb),
            showMin = c.showPerMin,
            ratingValue = offer.rating?.let { fmt2(it) } ?: "-",
            ratingColor = Grading.color(ratingGrade, cb),
            showRating = c.showRating,
            tripText = "U · " + tripText(offer),
            showTrip = c.showTrip,
            profitText = profitText,
            profitColor = if (profitGood) Grading.color(Grade.GOOD, cb) else Grading.color(Grade.BAD, cb),
            showProfit = profitText != null,
            borderColor = Grading.color(borderGrade, cb),
            bgColor = theme.bg,
            textColor = theme.text,
            subTextColor = theme.sub,
            alpha = c.cardOpacity.coerceIn(30, 100) / 100f,
            fontBase = c.fontSize.coerceIn(12, 22),
            durationMs = c.cardDurationSecs.coerceIn(0, 30) * 1000L,
            position = c.cardPosition,
            offsetYdp = c.offsetY,
        )
    }

    private fun postOfferNotification(context: Context, offer: TripOffer, settings: AppSettings) {
        val overall = Grading.overall(offer, settings.filters)
        val title = "$" + fmt2(offer.fare) + "  ·  " + overall.name
        val rating = offer.rating?.let { "  ★" + fmt2(it) } ?: ""
        val line = "$/mi " + fmt2(offer.perMile) + "   $/hr " + fmt2(offer.perHour) + rating
        val sub = tripText(offer)

        val builder = NotificationCompat.Builder(context, CHANNEL_OFFER)
            .setSmallIcon(R.drawable.ic_stat_cherry)
            .setContentTitle(title)
            .setContentText(line)
            .setStyle(NotificationCompat.BigTextStyle().bigText("$line\n$sub"))
            .setColor(0xFFFF6D2E.toInt())
            .setOnlyAlertOnce(true)
            .setContentIntent(openAppIntent(context))
            .setAutoCancel(true)

        offer.pickupAddress?.let { builder.addAction(0, "Board. Map", mapIntent(context, it, 11)) }
        offer.dropoffAddress?.let { builder.addAction(0, "Dest. Map", mapIntent(context, it, 12)) }
        notificationManager(context).notify(NOTIF_OFFER, builder.build())
    }

    private fun speakOffer(offer: TripOffer, settings: AppSettings) {
        if (!ttsReady) return
        val word = when (Grading.overall(offer, settings.filters)) {
            Grade.GOOD -> "Good"
            Grade.AVERAGE -> "Okay"
            Grade.BAD -> "Bad"
        }
        val phrase = "$word offer. ${fmt2(offer.fare)} dollars. " +
            "${fmt2(offer.perMile)} per mile. " +
            "${offer.totalMinutes.toInt()} minutes. " +
            String.format(Locale.US, "%.1f miles.", offer.totalMiles)
        tts?.speak(phrase, TextToSpeech.QUEUE_FLUSH, null, "offer")
    }

    // ---- helpers ----

    private data class ThemeColors(val bg: Int, val text: Int, val sub: Int)

    private fun themeColors(theme: CardTheme): ThemeColors = when (theme) {
        CardTheme.LIGHT -> ThemeColors(0xF2FFFFFF.toInt(), 0xFF111111.toInt(), 0xFF555555.toInt())
        CardTheme.DARK -> ThemeColors(0xF2111111.toInt(), 0xFFFFFFFF.toInt(), 0xFFB0B0B0.toInt())
        CardTheme.GREEN -> ThemeColors(0xF216A34A.toInt(), 0xFFFFFFFF.toInt(), 0xFFDCFCE7.toInt())
    }

    private fun tripText(offer: TripOffer): String {
        val totalMin = offer.totalMinutes.toInt()
        val h = totalMin / 60
        val m = totalMin % 60
        return String.format(Locale.US, "%dh%02dm · %.1fmi", h, m, offer.totalMiles)
    }

    private fun fmt2(v: Double): String = String.format(Locale.US, "%.2f", v)

    private fun mapIntent(context: Context, address: String, code: Int): PendingIntent {
        val uri = Uri.parse("geo:0,0?q=" + Uri.encode(address))
        val intent = Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return PendingIntent.getActivity(
            context, code, intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
    }

    fun openAppIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        return PendingIntent.getActivity(context, 1, intent, PendingIntent.FLAG_IMMUTABLE)
    }

    private fun notificationManager(context: Context): NotificationManager =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun ensureChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        notificationManager(context).createNotificationChannel(
            NotificationChannel(CHANNEL_OFFER, "Trip offers", NotificationManager.IMPORTANCE_DEFAULT)
                .apply { description = "Scanned trip offer metrics and map shortcuts" }
        )
    }
}
