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
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.gbsc.cherry.capture.ProjectionHolder
import com.gbsc.cherry.ui.theme.BrandOrange
import com.gbsc.cherry.ui.theme.GoodGreen

@Composable
fun HomeScreen(
    modifier: Modifier = Modifier,
    onStart: () -> Unit,
    onStop: () -> Unit,
    hasOverlayPermission: () -> Boolean,
) {
    val running by ProjectionHolder.isRunning.collectAsState()

    Column(
        modifier = modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(20.dp)
    ) {
        Text("CherryPick", fontSize = 30.sp, fontWeight = FontWeight.Bold)
        Text(
            "Know instantly if an Uber trip offer is worth accepting.",
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(20.dp))

        Card(
            colors = CardDefaults.cardColors(
                containerColor = if (running) GoodGreen.copy(alpha = 0.12f)
                else MaterialTheme.colorScheme.surfaceVariant
            )
        ) {
            Column(Modifier.padding(20.dp)) {
                Text(
                    if (running) "Scanning is ON" else "Scanning is OFF",
                    fontSize = 20.sp,
                    fontWeight = FontWeight.Bold,
                    color = if (running) GoodGreen else MaterialTheme.colorScheme.onSurface,
                )
                Spacer(Modifier.height(4.dp))
                Text(
                    if (running)
                        "Open Uber Driver. When an offer pops up, the card appears on top."
                    else
                        "Tap start, grant screen capture, then open Uber Driver.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.height(16.dp))
                if (running) {
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

        Spacer(Modifier.height(20.dp))
        PermissionRow("Display over other apps", hasOverlayPermission())

        Spacer(Modifier.height(20.dp))
        Text("How it works", fontWeight = FontWeight.Bold, fontSize = 16.sp)
        Spacer(Modifier.height(6.dp))
        Steps()

        Spacer(Modifier.height(24.dp))
        Text(
            "Tip: the offer reader is tuned for the US Uber Driver layout. If numbers look off, " +
                "adjust nothing in Uber — just fine-tune your goals under Filters.",
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
private fun Steps() {
    val steps = listOf(
        "Set your $/mile and $/hour goals in Filters.",
        "Enter your costs in Profit to see net profit per trip.",
        "Tap Start scanning and allow screen capture.",
        "Open Uber Driver and drive — the card grades each offer.",
    )
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        steps.forEachIndexed { i, s ->
            Text("${i + 1}.  $s", color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
