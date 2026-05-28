package com.gbsc.cherry.capture

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.provider.MediaStore
import android.speech.tts.TextToSpeech
import android.util.DisplayMetrics
import android.util.Log
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
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
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import java.util.Locale

class ScreenCaptureService : Service() {

    private lateinit var projectionManager: MediaProjectionManager
    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private lateinit var recognizer: TextRecognizer
    private lateinit var overlay: OverlayController
    private var tts: TextToSpeech? = null
    private var ttsReady = false

    private var bgThread: HandlerThread? = null
    private var bgHandler: Handler? = null

    private var width = 0
    private var height = 0
    private var densityDpi = 0

    @Volatile private var processing = false
    @Volatile private var lastProcess = 0L
    private var missCount = 0
    private var currentSignature: String? = null

    override fun onCreate() {
        super.onCreate()
        projectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        overlay = OverlayController(this)
        tts = TextToSpeech(this) { status ->
            if (status == TextToSpeech.SUCCESS) {
                tts?.language = Locale.US
                ttsReady = true
            }
        }
        ensureChannels()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopEverything()
            return START_NOT_STICKY
        }
        startForegroundCompat()

        val data = ProjectionHolder.data
        val code = ProjectionHolder.resultCode
        if (data == null) {
            Log.w(TAG, "No projection grant; stopping")
            stopEverything()
            return START_NOT_STICKY
        }

        if (mediaProjection == null) {
            mediaProjection = projectionManager.getMediaProjection(code, data)?.also { mp ->
                mp.registerCallback(projectionCallback, Handler(mainLooper))
            }
            if (mediaProjection == null) {
                Log.w(TAG, "getMediaProjection returned null")
                stopEverything()
                return START_NOT_STICKY
            }
            startCapture()
        }
        ProjectionHolder.isRunning.value = true
        return START_STICKY
    }

    private fun startCapture() {
        computeScreenSize()
        bgThread = HandlerThread("cherry-capture").apply { start() }
        bgHandler = Handler(bgThread!!.looper)

        val reader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)
        imageReader = reader
        virtualDisplay = mediaProjection?.createVirtualDisplay(
            "cherry-vd",
            width, height, densityDpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            reader.surface, null, bgHandler
        )
        reader.setOnImageAvailableListener({ r -> onImage(r) }, bgHandler)
    }

    private fun onImage(reader: ImageReader) {
        val image = reader.acquireLatestImage() ?: return
        val now = System.currentTimeMillis()
        if (processing || now - lastProcess < THROTTLE_MS) {
            image.close()
            return
        }
        processing = true
        val bmp = try {
            imageToBitmap(reader, image)
        } catch (t: Throwable) {
            Log.w(TAG, "imageToBitmap failed", t)
            null
        } finally {
            image.close()
        }
        if (bmp == null) {
            processing = false
            return
        }
        recognizer.process(InputImage.fromBitmap(bmp, 0))
            .addOnSuccessListener { result ->
                val isNew = try {
                    handleText(result.text)
                } catch (t: Throwable) {
                    Log.w(TAG, "handleText failed", t)
                    false
                }
                if (isNew && Repo.settings.value.customization.screenshotEnabled) {
                    runCatching { saveScreenshot(bmp) }
                }
                bmp.recycle()
                lastProcess = System.currentTimeMillis()
                processing = false
            }
            .addOnFailureListener {
                bmp.recycle()
                lastProcess = System.currentTimeMillis()
                processing = false
            }
    }

    /** Returns true when this frame surfaced a brand-new offer. */
    private fun handleText(text: String): Boolean {
        val parsed = OfferParser.parse(text)
        if (parsed == null) {
            missCount++
            if (missCount >= MISS_LIMIT) {
                currentSignature = null
                overlay.hide()
                notificationManager().cancel(NOTIF_OFFER)
            }
            return false
        }
        missCount = 0
        val offer = TripOffer(
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
        val signature = String.format(Locale.US, "%.2f|%.1f|%.0f", offer.fare, offer.totalMiles, offer.totalMinutes)
        val settings = Repo.settings.value

        overlay.show(buildOverlayData(offer, settings, signature))

        if (signature != currentSignature) {
            currentSignature = signature
            Repo.addOffer(offer)
            if (settings.customization.notificationEnabled) {
                postOfferNotification(offer, settings)
            }
            if (settings.customization.voiceEnabled) {
                speakOffer(offer, settings)
            }
            return true
        }
        return false
    }

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
            alpha = (c.cardOpacity.coerceIn(30, 100)) / 100f,
            fontBase = c.fontSize.coerceIn(12, 22),
            durationMs = c.cardDurationSecs.coerceIn(0, 30) * 1000L,
            position = c.cardPosition,
            offsetYdp = c.offsetY,
        )
    }

    private data class ThemeColors(val bg: Int, val text: Int, val sub: Int)

    private fun themeColors(theme: CardTheme): ThemeColors = when (theme) {
        CardTheme.LIGHT -> ThemeColors(0xF2FFFFFF.toInt(), 0xFF111111.toInt(), 0xFF555555.toInt())
        CardTheme.DARK -> ThemeColors(0xF2111111.toInt(), 0xFFFFFFFF.toInt(), 0xFFB0B0B0.toInt())
        CardTheme.GREEN -> ThemeColors(0xF216A34A.toInt(), 0xFFFFFFFF.toInt(), 0xFFDCFCE7.toInt())
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

    private fun saveScreenshot(bmp: Bitmap) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        val name = "cherrypick_" + System.currentTimeMillis() + ".jpg"
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, name)
            put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
            put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/CherryPick")
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val resolver = contentResolver
        val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values) ?: return
        resolver.openOutputStream(uri)?.use { out ->
            bmp.compress(Bitmap.CompressFormat.JPEG, 90, out)
        }
        values.clear()
        values.put(MediaStore.Images.Media.IS_PENDING, 0)
        resolver.update(uri, values, null, null)
    }

    private fun postOfferNotification(offer: TripOffer, settings: AppSettings) {
        val overall = Grading.overall(offer, settings.filters)
        val title = "$" + fmt2(offer.fare) + "  ·  " + overall.name
        val rating = offer.rating?.let { "  ★" + fmt2(it) } ?: ""
        val line = "$/mi " + fmt2(offer.perMile) + "   $/hr " + fmt2(offer.perHour) + rating
        val sub = tripText(offer)

        val builder = NotificationCompat.Builder(this, CHANNEL_OFFER)
            .setSmallIcon(R.drawable.ic_stat_cherry)
            .setContentTitle(title)
            .setContentText(line)
            .setStyle(NotificationCompat.BigTextStyle().bigText("$line\n$sub"))
            .setColor(0xFFFF6D2E.toInt())
            .setOnlyAlertOnce(true)
            .setContentIntent(openAppIntent())
            .setAutoCancel(true)

        offer.pickupAddress?.let {
            builder.addAction(0, "Board. Map", mapIntent(it, 11))
        }
        offer.dropoffAddress?.let {
            builder.addAction(0, "Dest. Map", mapIntent(it, 12))
        }
        notificationManager().notify(NOTIF_OFFER, builder.build())
    }

    // ---- helpers ----

    private fun tripText(offer: TripOffer): String {
        val totalMin = offer.totalMinutes.toInt()
        val h = totalMin / 60
        val m = totalMin % 60
        return String.format(Locale.US, "%dh%02dm · %.1fmi", h, m, offer.totalMiles)
    }

    private fun fmt2(v: Double): String = String.format(Locale.US, "%.2f", v)

    private fun mapIntent(address: String, code: Int): PendingIntent {
        val uri = Uri.parse("geo:0,0?q=" + Uri.encode(address))
        val intent = Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return PendingIntent.getActivity(
            this, code, intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
    }

    private fun openAppIntent(): PendingIntent {
        val intent = Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        return PendingIntent.getActivity(this, 1, intent, PendingIntent.FLAG_IMMUTABLE)
    }

    private fun computeScreenSize() {
        val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        densityDpi = resources.displayMetrics.densityDpi
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bounds = wm.currentWindowMetrics.bounds
            width = bounds.width()
            height = bounds.height()
        } else {
            val dm = DisplayMetrics()
            @Suppress("DEPRECATION")
            wm.defaultDisplay.getRealMetrics(dm)
            width = dm.widthPixels
            height = dm.heightPixels
        }
        if (width <= 0) width = resources.displayMetrics.widthPixels
        if (height <= 0) height = resources.displayMetrics.heightPixels
    }

    private fun imageToBitmap(reader: ImageReader, image: android.media.Image): Bitmap {
        val plane = image.planes[0]
        val buffer = plane.buffer
        val pixelStride = plane.pixelStride
        val rowStride = plane.rowStride
        val rowPadding = rowStride - pixelStride * reader.width
        val bmp = Bitmap.createBitmap(
            reader.width + rowPadding / pixelStride,
            reader.height,
            Bitmap.Config.ARGB_8888
        )
        bmp.copyPixelsFromBuffer(buffer)
        return if (rowPadding == 0) {
            bmp
        } else {
            val cropped = Bitmap.createBitmap(bmp, 0, 0, reader.width, reader.height)
            if (cropped != bmp) bmp.recycle()
            cropped
        }
    }

    private fun startForegroundCompat() {
        val notif = buildServiceNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIF_FG, notif,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
            )
        } else {
            startForeground(NOTIF_FG, notif)
        }
    }

    private fun buildServiceNotification(): Notification {
        val stopIntent = Intent(this, ServiceControlReceiver::class.java).setAction(ACTION_STOP)
        val stopPending = PendingIntent.getBroadcast(
            this, 0, stopIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        return NotificationCompat.Builder(this, CHANNEL_CAPTURE)
            .setSmallIcon(R.drawable.ic_stat_cherry)
            .setContentTitle("CherryPick is scanning")
            .setContentText("Watching for Uber trip offers")
            .setColor(0xFFFF6D2E.toInt())
            .setOngoing(true)
            .setContentIntent(openAppIntent())
            .addAction(0, "Stop", stopPending)
            .build()
    }

    private fun ensureChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val mgr = notificationManager()
        val capture = NotificationChannel(
            CHANNEL_CAPTURE, "Scanning", NotificationManager.IMPORTANCE_LOW
        ).apply { description = "Persistent notification while CherryPick is scanning" }
        val offer = NotificationChannel(
            CHANNEL_OFFER, "Trip offers", NotificationManager.IMPORTANCE_DEFAULT
        ).apply { description = "Shows scanned trip offer metrics and map shortcuts" }
        mgr.createNotificationChannel(capture)
        mgr.createNotificationChannel(offer)
    }

    private fun notificationManager(): NotificationManager =
        getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private val projectionCallback = object : MediaProjection.Callback() {
        override fun onStop() {
            stopEverything()
        }
    }

    private fun stopEverything() {
        ProjectionHolder.isRunning.value = false
        runCatching { overlay.destroy() }
        runCatching { virtualDisplay?.release() }
        virtualDisplay = null
        runCatching { imageReader?.close() }
        imageReader = null
        runCatching { mediaProjection?.unregisterCallback(projectionCallback) }
        runCatching { mediaProjection?.stop() }
        mediaProjection = null
        bgThread?.quitSafely()
        bgThread = null
        bgHandler = null
        notificationManager().cancel(NOTIF_OFFER)
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        runCatching { recognizer.close() }
        runCatching { tts?.stop(); tts?.shutdown() }
        tts = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        private const val TAG = "ScreenCaptureService"
        const val ACTION_STOP = "com.gbsc.cherry.STOP"
        private const val CHANNEL_CAPTURE = "capture"
        private const val CHANNEL_OFFER = "offer"
        private const val NOTIF_FG = 1
        private const val NOTIF_OFFER = 2
        private const val THROTTLE_MS = 800L
        private const val MISS_LIMIT = 3

        fun start(context: Context) {
            val intent = Intent(context, ScreenCaptureService::class.java)
            ContextCompat.startForegroundService(context, intent)
        }

        fun stop(context: Context) {
            val intent = Intent(context, ScreenCaptureService::class.java).setAction(ACTION_STOP)
            context.startService(intent)
        }
    }
}
