package com.gbsc.cherry.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Error
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.gbsc.cherry.capture.OfferEngine
import com.gbsc.cherry.ui.theme.BrandOrange
import com.gbsc.cherry.ui.theme.GoodGreen

@Composable
fun HomeScreen(
    modifier: Modifier = Modifier,
    onStart: () -> Unit,
    onStop: () -> Unit,
    onTestOffer: () -> Unit,
    hasOverlayPermission: () -> Boolean,
    isAccessibilityEnabled: () -> Boolean,
    openAccessibilitySettings: () -> Unit,
) {
    val scanning by OfferEngine.scanning.collectAsState()

    Column(
        modifier = modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(20.dp)
    ) {
        Text("CherryPick", fontSize = 30.sp, fontWeight = FontWeight.Bold)
        Text(
            "Reads Uber Driver offers in real time — no screen sharing required.",
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(20.dp))

        Card(
            colors = CardDefaults.cardColors(
                containerColor = if (scanning) GoodGreen.copy(alpha = 0.12f)
                else MaterialTheme.colorScheme.surfaceVariant
            )
        ) {
            Column(Modifier.padding(20.dp)) {
                Text(
                    if (scanning) "Scanning is ON" else "Scanning is OFF",
                    fontSize = 20.sp,
                    fontWeight = FontWeight.Bold,
                    color = if (scanning) GoodGreen else MaterialTheme.colorScheme.onSurface,
                )
                Spacer(Modifier.height(4.dp))
                Text(
                    if (scanning)
                        "Open Uber Driver. When an offer pops up, the card appears on top."
                    else
                        "Tap Start — you'll grant overlay + accessibility once, then it just works.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.height(16.dp))
                if (scanning) {
                    OutlinedButton(onClick = onStop, modifier = Modifier.fillMaxWidth()) {
                        Text("Stop scanning")
                    }
                } else {
                    Button(
                        onClick = onStart,
                        modifier = Modifier.fillMaxWidth(),
                        colors = ButtonDefaults.buttonColors(containerColor = BrandOrange),
                    ) {
                        Text("Start scanning")
                    }
                }
            }
        }

        Spacer(Modifier.height(12.dp))
        OutlinedButton(onClick = onTestOffer, modifier = Modifier.fillMaxWidth()) {
            Text("Show test offer")
        }
        Text(
            "Pushes a sample offer through the card, notification, and voice so you can dry-run the look and feel without going online.",
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            fontSize = 12.sp,
            modifier = Modifier.padding(top = 4.dp),
        )

        Spacer(Modifier.height(20.dp))
        Text("Permissions", fontWeight = FontWeight.Bold, fontSize = 16.sp)
        Spacer(Modifier.height(6.dp))
        PermissionRow("Display over other apps", hasOverlayPermission())
        Spacer(Modifier.height(4.dp))
        AccessibilityRow(isAccessibilityEnabled(), openAccessibilitySettings)

        Spacer(Modifier.height(20.dp))
        Diagnostic()

        Spacer(Modifier.height(20.dp))
        Text("How it works", fontWeight = FontWeight.Bold, fontSize = 16.sp)
        Spacer(Modifier.height(6.dp))
        Steps()

        Spacer(Modifier.height(24.dp))
        Text(
            "Because CherryPick reads Uber via the accessibility service (not screen sharing), " +
                "Android won't grey out your other notifications while you drive.",
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            fontSize = 13.sp,
        )
    }
}

@Composable
private fun PermissionRow(label: String, granted: Boolean) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(
            if (granted) Icons.Filled.CheckCircle else Icons.Filled.Error,
            contentDescription = null,
            tint = if (granted) GoodGreen else MaterialTheme.colorScheme.error,
            modifier = Modifier.size(20.dp),
        )
        Spacer(Modifier.size(8.dp))
        Text(if (granted) "$label — granted" else "$label — needed on start")
    }
}

@Composable
private fun AccessibilityRow(enabled: Boolean, openSettings: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(
            if (enabled) Icons.Filled.CheckCircle else Icons.Filled.Error,
            contentDescription = null,
            tint = if (enabled) GoodGreen else MaterialTheme.colorScheme.error,
            modifier = Modifier.size(20.dp),
        )
        Spacer(Modifier.size(8.dp))
        Text(
            if (enabled) "Accessibility service — enabled"
            else "Accessibility service — needed to read Uber",
            modifier = Modifier.weight(1f),
        )
        if (!enabled) {
            TextButton(onClick = openSettings) { Text("Enable") }
        }
    }
}

@Composable
private fun Diagnostic() {
    val debug by OfferEngine.lastDebug.collectAsState()
    val seen by OfferEngine.lastSeenPkg.collectAsState()
    Text("Diagnostic", fontWeight = FontWeight.Bold, fontSize = 16.sp)
    Spacer(Modifier.height(6.dp))
    if (debug == null) {
        Text(
            "No Uber events captured yet. Open Uber Driver — if this stays blank, turn on Debug mode in Card → Advanced.",
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            fontSize = 13.sp,
        )
    } else {
        val d = debug!!
        val parsedLabel = if (d.parsed) "YES (\$%.2f)".format(d.fare) else "NO"
        Text("Last Uber screen — Package: ${d.pkg ?: "—"}", fontSize = 13.sp)
        Text(
            "Text: ${d.textChars} chars  ·  Parsed: $parsedLabel",
            fontSize = 13.sp,
            color = if (d.parsed) GoodGreen else MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            "Preview: ${d.textPreview}",
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            fontSize = 12.sp,
        )
    }
    seen?.let {
        Spacer(Modifier.height(4.dp))
        Text(
            "Most recent foreground app: $it",
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            fontSize = 12.sp,
        )
    }
    val recent by OfferEngine.recentPackages.collectAsState()
    if (recent.isNotEmpty()) {
        Spacer(Modifier.height(6.dp))
        Text(
            "Recent packages seen (newest first):",
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            fontSize = 12.sp,
        )
        recent.forEach { pkg ->
            Text("• $pkg", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 12.sp)
        }
    }
}

@Composable
private fun Steps() {
    val steps = listOf(
        "Set your $/mile and $/hour goals in Filters.",
        "Enter your costs in Profit to see net profit per trip.",
        "Tap Start scanning and grant overlay + accessibility permissions.",
        "Open Uber Driver and drive — the card grades each offer.",
    )
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        steps.forEachIndexed { i, s ->
            Text("${i + 1}.  $s", color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
