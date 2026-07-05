package com.gbsc.cherry.accessibility

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.graphics.Bitmap
import android.os.Build
import android.view.Display
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import com.gbsc.cherry.capture.OfferEngine
import com.gbsc.cherry.data.Repo
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.cancel

/**
 * Reads the live Uber Driver offer card from the accessibility node tree.
 *
 * Replaces the older MediaProjection screen-capture path so Android does not flip into
 * its "screen is being shared" privacy state, which would otherwise mute notifications
 * and overlay a persistent system banner while you drive.
 */
class UberAccessibilityService : AccessibilityService() {

    private var lastProcessed = 0L
    private var lastSeenUpdate = 0L
    private var lastOcrTime = 0L
    @Volatile private var ocrInFlight = false
    private val recognizer: TextRecognizer by lazy {
        TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
    }
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var settingsJob: Job? = null
    private var pollJob: Job? = null

    override fun onServiceConnected() {
        super.onServiceConnected()
        OfferEngine.ensureInit(this)
        OfferEngine.accessibilityConnected.value = true
        settingsJob?.cancel()
        settingsJob = scope.launch {
            Repo.settings
                .map { it.customization.debugMode }
                .distinctUntilChanged()
                .collect { applyServiceInfo(it) }
        }
        pollJob?.cancel()
        pollJob = scope.launch {
            // Re-read the active Uber window once per second while scanning so we catch
            // offer cards that never fire accessibility events after the initial pop.
            OfferEngine.scanning.collectLatest { isScanning ->
                if (!isScanning) return@collectLatest
                while (isActive) {
                    delay(POLL_MS)
                    captureAndProcess(forceProcess = false, bypassThrottle = true)
                    OfferEngine.pollCount.value = OfferEngine.pollCount.value + 1
                }
            }
        }
    }

    override fun onUnbind(intent: Intent?): Boolean {
        settingsJob?.cancel()
        settingsJob = null
        pollJob?.cancel()
        pollJob = null
        OfferEngine.accessibilityConnected.value = false
        OfferEngine.resetState()
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        scope.cancel()
        runCatching { recognizer.close() }
        super.onDestroy()
    }

    override fun onInterrupt() {}

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        val force = event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
        captureAndProcess(forceProcess = force, bypassThrottle = false)
    }

    private fun captureAndProcess(forceProcess: Boolean, bypassThrottle: Boolean) {
        val activeRoot = rootInActiveWindow
        var sawUberWindow = false
        var activePkg: String? = null
        val activeIsUber = activeRoot != null && isUberPackage(activeRoot.packageName?.toString())
        val sb = StringBuilder()
        val classes = linkedSetOf<String>()
        var nodeCount = 0
        val winSummary = StringBuilder()
        val seenWindowIds = mutableSetOf<Int>()

        // 1) Iterate every visible window. Some devices/configurations don't surface the
        //    offer card via rootInActiveWindow even when it's foreground, so we walk
        //    everything and collect text from any Uber-package root we find. For
        //    non-Uber windows we only count nodes (no text read) so we still see what
        //    else is on screen in the diagnostic without reading other apps.
        for (w in windows) {
            val r = w.root ?: continue
            val pkg = r.packageName?.toString() ?: "—"
            val nodes = if (isUberPackage(pkg)) {
                collectText(r, sb, classes)
            } else {
                countNodes(r)
            }
            if (winSummary.isNotEmpty()) winSummary.append("  ")
            winSummary.append("$pkg:$nodes")
            seenWindowIds.add(w.id)
            if (isUberPackage(pkg)) {
                sawUberWindow = true
                if (activePkg == null) activePkg = pkg
                nodeCount += nodes
            }
        }
        // 2) Also pull in the active window if it wasn't already in the windows list.
        //    Dedupe by window id: fresh AccessibilityNodeInfo instances for the same
        //    window are never identical references, so an identity check would read
        //    (and count) the active window's text twice.
        if (activeRoot != null && activeRoot.windowId !in seenWindowIds) {
            val pkg = activeRoot.packageName?.toString() ?: "—"
            val nodes = if (isUberPackage(pkg)) {
                collectText(activeRoot, sb, classes)
            } else {
                countNodes(activeRoot)
            }
            if (winSummary.isNotEmpty()) winSummary.append("  ")
            winSummary.append("active:$pkg:$nodes")
            if (isUberPackage(pkg)) {
                sawUberWindow = true
                if (activePkg == null) activePkg = pkg
                nodeCount += nodes
            }
        }

        val now = System.currentTimeMillis()

        if (sawUberWindow) {
            if (!forceProcess && !bypassThrottle && now - lastProcessed < THROTTLE_MS) return
            lastProcessed = now

            val text = sb.toString()
            val classSummary = classes.take(6).joinToString(", ")
            OfferEngine.recordDebug(
                pkg = activePkg,
                text = text,
                nodeCount = nodeCount,
                classes = classSummary,
                windowsSummary = winSummary.toString(),
                isUber = true,
            )

            if (!OfferEngine.scanning.value) return

            val accLooksLikeOffer = OfferEngine.looksLikeOffer(text)
            if (text.isNotBlank() && accLooksLikeOffer) {
                val isNew = OfferEngine.processText(text)
                if (isNew &&
                    Repo.settings.value.customization.screenshotEnabled &&
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.R
                ) {
                    captureScreenshot()
                }
            } else if (activeIsUber) {
                // Uber visible AND in the foreground AND accessibility doesn't have
                // the offer text. Two trigger paths:
                //   - WINDOW_STATE_CHANGED (forceProcess=true): an offer card just
                //     animated in — fire OCR immediately, bypassing the throttle, so
                //     the user has the full time window to decide.
                //   - Otherwise: small accessibility text is the signature of Uber
                //     hiding the offer card, so we throttled-OCR.
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
                    (forceProcess || text.length < OCR_TEXT_THRESHOLD)
                ) {
                    maybeRunOcr(force = forceProcess)
                } else if (text.isNotBlank()) {
                    // Substantial accessibility text with no offer shape — Uber is back
                    // on a normal screen (dashboard/map), so the offer expired. Tell the
                    // engine (debounced there) to drop the card and notification.
                    OfferEngine.onNoOffer()
                }
            }
        } else if (Repo.settings.value.customization.debugMode) {
            if (now - lastSeenUpdate < SEEN_THROTTLE_MS) return
            lastSeenUpdate = now
            OfferEngine.recordSeenPkg(activeRoot?.packageName?.toString())
            // Even outside of Uber, surface the window list for diagnostics.
            OfferEngine.recordDebug(
                pkg = activeRoot?.packageName?.toString(),
                text = "",
                nodeCount = 0,
                classes = "",
                windowsSummary = winSummary.toString(),
            )
        }
    }

    private fun applyServiceInfo(debugMode: Boolean) {
        val info = serviceInfo ?: return
        info.packageNames = if (debugMode) null else UBER_PACKAGES
        serviceInfo = info
    }

    private fun countNodes(node: AccessibilityNodeInfo?): Int {
        if (node == null) return 0
        var count = 1
        try {
            for (i in 0 until node.childCount) {
                count += countNodes(node.getChild(i))
            }
        } catch (_: Throwable) {
        }
        return count
    }

    private fun collectText(
        node: AccessibilityNodeInfo?,
        sb: StringBuilder,
        classes: MutableSet<String> = mutableSetOf(),
    ): Int {
        if (node == null) return 0
        var count = 1
        try {
            node.text?.toString()?.trim().takeUnless { it.isNullOrEmpty() }?.let {
                sb.append(it).append('\n')
            }
            node.contentDescription?.toString()?.trim().takeUnless { it.isNullOrEmpty() }?.let {
                sb.append(it).append('\n')
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                node.hintText?.toString()?.trim().takeUnless { it.isNullOrEmpty() }?.let {
                    sb.append(it).append('\n')
                }
                node.tooltipText?.toString()?.trim().takeUnless { it.isNullOrEmpty() }?.let {
                    sb.append(it).append('\n')
                }
            }
            node.className?.toString()?.substringAfterLast('.')?.let { classes.add(it) }
            for (i in 0 until node.childCount) {
                count += collectText(node.getChild(i), sb, classes)
            }
        } catch (_: Throwable) {
            // Nodes can be recycled mid-traversal; the next event will replay.
        }
        return count
    }

    private fun captureScreenshot() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        takeScreenshot(
            Display.DEFAULT_DISPLAY,
            mainExecutor,
            object : TakeScreenshotCallback {
                override fun onSuccess(screenshot: ScreenshotResult) {
                    try {
                        val bmp = Bitmap.wrapHardwareBuffer(
                            screenshot.hardwareBuffer,
                            screenshot.colorSpace
                        )
                        bmp?.let { OfferEngine.saveScreenshot(it) }
                    } finally {
                        runCatching { screenshot.hardwareBuffer.close() }
                    }
                }

                override fun onFailure(errorCode: Int) {}
            }
        )
    }

    private fun maybeRunOcr(force: Boolean = false) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        val now = System.currentTimeMillis()
        if (ocrInFlight) return
        if (!force && now - lastOcrTime < OCR_THROTTLE_MS) return
        lastOcrTime = now
        ocrInFlight = true
        takeScreenshot(
            Display.DEFAULT_DISPLAY,
            mainExecutor,
            object : TakeScreenshotCallback {
                override fun onSuccess(screenshot: ScreenshotResult) {
                    val bmp = Bitmap.wrapHardwareBuffer(
                        screenshot.hardwareBuffer,
                        screenshot.colorSpace
                    )
                    runCatching { screenshot.hardwareBuffer.close() }
                    if (bmp == null) {
                        ocrInFlight = false
                        return
                    }
                    recognizer.process(InputImage.fromBitmap(bmp, 0))
                        .addOnSuccessListener { result ->
                            val ocrText = result.text
                            OfferEngine.recordOcrText(ocrText)
                            if (OfferEngine.scanning.value) {
                                if (OfferEngine.looksLikeOffer(ocrText)) {
                                    OfferEngine.processText(ocrText)
                                } else {
                                    // OCR confirms there's no offer on screen either.
                                    OfferEngine.onNoOffer()
                                }
                            }
                            bmp.recycle()
                            ocrInFlight = false
                        }
                        .addOnFailureListener {
                            bmp.recycle()
                            ocrInFlight = false
                        }
                }

                override fun onFailure(errorCode: Int) {
                    ocrInFlight = false
                }
            }
        )
    }

    companion object {
        private const val THROTTLE_MS = 500L
        private const val SEEN_THROTTLE_MS = 500L
        private const val POLL_MS = 1000L
        private const val OCR_THROTTLE_MS = 800L
        private const val OCR_TEXT_THRESHOLD = 500
        private val UBER_PACKAGES = arrayOf(
            "com.ubercab.driver",
            "com.uber.driver",
            "com.ubercab.driverapp",
        )

        private fun isUberPackage(pkg: String?): Boolean =
            pkg != null && UBER_PACKAGES.any { it == pkg }
    }
}
