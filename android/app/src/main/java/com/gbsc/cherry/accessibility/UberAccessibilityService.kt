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

/**
 * Reads the live Uber Driver offer card from the accessibility node tree.
 *
 * Replaces the older MediaProjection screen-capture path so Android does not flip into
 * its "screen is being shared" privacy state, which would otherwise mute notifications
 * and overlay a persistent system banner while you drive.
 */
class UberAccessibilityService : AccessibilityService() {

    private var lastProcessed = 0L

    override fun onServiceConnected() {
        super.onServiceConnected()
        OfferEngine.ensureInit(this)
        OfferEngine.accessibilityConnected.value = true
    }

    override fun onUnbind(intent: Intent?): Boolean {
        OfferEngine.accessibilityConnected.value = false
        OfferEngine.resetState()
        return super.onUnbind(intent)
    }

    override fun onInterrupt() {}

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        if (!OfferEngine.scanning.value) return
        val now = System.currentTimeMillis()
        if (now - lastProcessed < THROTTLE_MS) return
        lastProcessed = now

        val root = rootInActiveWindow ?: return
        val sb = StringBuilder()
        collectText(root, sb)
        if (sb.isBlank()) return

        val isNew = OfferEngine.processText(sb.toString())
        if (isNew &&
            Repo.settings.value.customization.screenshotEnabled &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.R
        ) {
            captureScreenshot()
        }
    }

    private fun collectText(node: AccessibilityNodeInfo?, sb: StringBuilder) {
        if (node == null) return
        try {
            node.text?.toString()?.trim().takeUnless { it.isNullOrEmpty() }?.let {
                sb.append(it).append('\n')
            }
            node.contentDescription?.toString()?.trim().takeUnless { it.isNullOrEmpty() }?.let {
                sb.append(it).append('\n')
            }
            for (i in 0 until node.childCount) {
                collectText(node.getChild(i), sb)
            }
        } catch (_: Throwable) {
            // Nodes can be recycled mid-traversal; the next event will replay.
        }
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
    }
}
