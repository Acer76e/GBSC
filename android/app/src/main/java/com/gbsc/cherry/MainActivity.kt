package com.gbsc.cherry

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import com.gbsc.cherry.capture.OfferEngine
import com.gbsc.cherry.ui.CherryApp
import com.gbsc.cherry.ui.theme.CherryTheme

class MainActivity : ComponentActivity() {

    private val overlayLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) {
        // No-op: the Start button rechecks the gates each time the user taps it.
    }

    private val notifLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) {}

    private val accessibilityLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) {}

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            CherryTheme {
                CherryApp(
                    onStart = { startMonitoring() },
                    onStop = { OfferEngine.scanning.value = false },
                    hasOverlayPermission = { Settings.canDrawOverlays(this) },
                    isAccessibilityEnabled = { isAccessibilityServiceEnabled(this) },
                    openAccessibilitySettings = { openAccessibilitySettings() },
                )
            }
        }
    }

    private fun startMonitoring() {
        if (!Settings.canDrawOverlays(this)) {
            overlayLauncher.launch(
                Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:$packageName")
                )
            )
            toast("Allow CherryPick to display over other apps, then tap Start again")
            return
        }
        if (!isAccessibilityServiceEnabled(this)) {
            openAccessibilitySettings()
            toast("Turn on CherryPick under Accessibility, then return and tap Start")
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
            != PackageManager.PERMISSION_GRANTED
        ) {
            notifLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
        OfferEngine.scanning.value = true
    }

    private fun openAccessibilitySettings() {
        accessibilityLauncher.launch(
            Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }

    private fun toast(msg: String) = Toast.makeText(this, msg, Toast.LENGTH_LONG).show()

    companion object {
        private const val SERVICE_ID = "com.gbsc.cherry/com.gbsc.cherry.accessibility.UberAccessibilityService"

        fun isAccessibilityServiceEnabled(context: Context): Boolean {
            val enabled = Settings.Secure.getString(
                context.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            ) ?: return false
            return enabled.split(':').any { it.equals(SERVICE_ID, ignoreCase = true) }
        }
    }
}
