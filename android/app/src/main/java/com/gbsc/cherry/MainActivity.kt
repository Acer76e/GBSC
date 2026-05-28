package com.gbsc.cherry

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import com.gbsc.cherry.capture.ProjectionHolder
import com.gbsc.cherry.capture.ScreenCaptureService
import com.gbsc.cherry.ui.CherryApp
import com.gbsc.cherry.ui.theme.CherryTheme

class MainActivity : ComponentActivity() {

    private val projectionManager by lazy {
        getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
    }

    private var pendingStart = false
    private var awaitingNotif = false

    private val overlayLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) {
        if (pendingStart && Settings.canDrawOverlays(this)) {
            pendingStart = false
            ensureNotifThenProject()
        } else if (pendingStart) {
            pendingStart = false
            toast("Overlay permission is required to show the trip card")
        }
    }

    private val notifLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) {
        if (awaitingNotif) {
            awaitingNotif = false
            launchProjection()
        }
    }

    private val projectionLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK && result.data != null) {
            ProjectionHolder.resultCode = result.resultCode
            ProjectionHolder.data = result.data
            ScreenCaptureService.start(this)
        } else {
            toast("Screen capture permission denied")
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            CherryTheme {
                CherryApp(
                    onStart = { startMonitoring() },
                    onStop = { ScreenCaptureService.stop(this) },
                    hasOverlayPermission = { Settings.canDrawOverlays(this) },
                )
            }
        }
    }

    private fun startMonitoring() {
        if (!Settings.canDrawOverlays(this)) {
            pendingStart = true
            overlayLauncher.launch(
                Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:$packageName")
                )
            )
            toast("Allow CherryPick to display over other apps, then return")
            return
        }
        ensureNotifThenProject()
    }

    private fun ensureNotifThenProject() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
            != PackageManager.PERMISSION_GRANTED
        ) {
            awaitingNotif = true
            notifLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            launchProjection()
        }
    }

    private fun launchProjection() {
        projectionLauncher.launch(projectionManager.createScreenCaptureIntent())
    }

    private fun toast(msg: String) = Toast.makeText(this, msg, Toast.LENGTH_LONG).show()
}
