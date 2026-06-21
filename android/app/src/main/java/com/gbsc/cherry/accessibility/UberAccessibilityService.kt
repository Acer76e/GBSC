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
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
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
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var settingsJob: Job? = null

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
    }

    override fun onUnbind(intent: Intent?): Boolean {
        settingsJob?.cancel()
        settingsJob = null
        OfferEngine.accessibilityConnected.value = false
        OfferEngine.resetState()
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    override fun onInterrupt() {}

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        // Primary check: the actively focused window. The getWindows() iteration below
        // can return empty or stale entries depending on the device, so we trust
        // rootInActiveWindow as the source of truth and use windows only as a supplement
        // (e.g. for an offer dialog that pops as its own window).
        val activeRoot = rootInActiveWindow
        var sawUberWindow = false
        var activePkg: String? = null
        val sb = StringBuilder()
        val classes = linkedSetOf<String>()
        var nodeCount = 0

        if (activeRoot != null && isUberPackage(activeRoot.packageName?.toString())) {
            sawUberWindow = true
            activePkg = activeRoot.packageName?.toString()
            nodeCount += collectText(activeRoot, sb, classes)
        }
        for (w in windows) {
            val r = w.root ?: continue
            if (r === activeRoot) continue
            val pkg = r.packageName?.toString()
            if (isUberPackage(pkg)) {
                sawUberWindow = true
                if (activePkg == null) activePkg = pkg
                nodeCount += collectText(r, sb, classes)
            }
        }

        val now = System.currentTimeMillis()

        if (sawUberWindow) {
            // Never throttle the WINDOW_STATE_CHANGED that fires when the user switches
            // to Uber or when the offer card pops as a new window — those are exactly
            // the events we don't want to miss.
            val forceProcess = event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
            if (!forceProcess && now - lastProcessed < THROTTLE_MS) return
            lastProcessed = now

            val text = sb.toString()
            val classSummary = classes.take(6).joinToString(", ")
            OfferEngine.recordDebug(activePkg, text, nodeCount, classSummary)

            if (!OfferEngine.scanning.value) return
            if (text.isBlank()) return

            val isNew = OfferEngine.processText(text)
            if (isNew &&
                Repo.settings.value.customization.screenshotEnabled &&
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.R
            ) {
                captureScreenshot()
            }
        } else if (Repo.settings.value.customization.debugMode) {
            // Non-Uber window — throttle the diagnostic update separately from Uber
            // processing so a chatty foreground app (incl. CherryPick itself) can't
            // starve real Uber events.
            if (now - lastSeenUpdate < SEEN_THROTTLE_MS) return
            lastSeenUpdate = now
            OfferEngine.recordSeenPkg(activeRoot?.packageName?.toString())
        }
    }

    private fun applyServiceInfo(debugMode: Boolean) {
        val info = serviceInfo ?: return
        info.packageNames = if (debugMode) null else UBER_PACKAGES
        serviceInfo = info
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

    companion object {
        private const val THROTTLE_MS = 500L
        private const val SEEN_THROTTLE_MS = 500L
        private val UBER_PACKAGES = arrayOf(
            "com.ubercab.driver",
            "com.uber.driver",
            "com.ubercab.driverapp",
        )

        private fun isUberPackage(pkg: String?): Boolean =
            pkg != null && UBER_PACKAGES.any { it == pkg }
    }
}
