package com.gbsc.cherry.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.gbsc.cherry.data.CardPosition
import com.gbsc.cherry.data.CardTheme
import com.gbsc.cherry.data.Customization
import com.gbsc.cherry.data.Repo

@Composable
fun SettingsScreen(modifier: Modifier = Modifier) {
    val settings by Repo.settings.collectAsState()
    val c = settings.customization

    fun update(transform: (Customization) -> Customization) {
        Repo.updateSettings { it.copy(customization = transform(it.customization)) }
    }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(20.dp)
    ) {
        Text("Customize the Card", fontSize = 26.sp, fontWeight = FontWeight.Bold)
        Text(
            "Choose where the card sits, how it looks, and which info it shows.",
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(16.dp))

        Text("Card position", fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            CardPosition.entries.forEach { pos ->
                FilterChip(
                    selected = c.cardPosition == pos,
                    onClick = { update { it.copy(cardPosition = pos) } },
                    label = { Text(pos.name.titlecase()) },
                )
            }
        }

        Spacer(Modifier.height(16.dp))
        Text("Card theme", fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            CardTheme.entries.forEach { theme ->
                FilterChip(
                    selected = c.cardTheme == theme,
                    onClick = { update { it.copy(cardTheme = theme) } },
                    label = { Text(theme.name.titlecase()) },
                )
            }
        }

        Spacer(Modifier.height(16.dp))
        IntSlider("Font size", c.fontSize, 12, 22, "") { update { o -> o.copy(fontSize = it) } }
        IntSlider("Card opacity", c.cardOpacity, 30, 100, "%") { update { o -> o.copy(cardOpacity = it) } }
        IntSlider("Auto-hide after", c.cardDurationSecs, 3, 15, "s") { update { o -> o.copy(cardDurationSecs = it) } }

        Text("Card vertical offset", fontWeight = FontWeight.Bold)
        Slider(
            value = c.offsetY.toFloat(),
            onValueChange = { update { o -> o.copy(offsetY = it.toInt()) } },
            valueRange = 0f..500f,
        )

        Spacer(Modifier.height(12.dp))
        Text("Shown on the card", fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(4.dp))
        ToggleRow("Earnings per mile (\$/mi)", c.showPerMile) { v -> update { it.copy(showPerMile = v) } }
        ToggleRow("Earnings per hour (\$/hr)", c.showPerHour) { v -> update { it.copy(showPerHour = v) } }
        ToggleRow("Earnings per minute (\$/min)", c.showPerMin) { v -> update { it.copy(showPerMin = v) } }
        ToggleRow("Passenger rating", c.showRating) { v -> update { it.copy(showRating = v) } }
        ToggleRow("Trip distance & time", c.showTrip) { v -> update { it.copy(showTrip = v) } }
        ToggleRow("Profit (\$)", c.showProfit) { v -> update { it.copy(showProfit = v) } }
        ToggleRow("Profit %", c.showProfitPct) { v -> update { it.copy(showProfitPct = v) } }
        ToggleRow("Profit per hour", c.showProfitPerHour) { v -> update { it.copy(showProfitPerHour = v) } }

        Spacer(Modifier.height(12.dp))
        Text("Accessibility", fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(4.dp))
        ToggleRow("Colorblind palette (blue/yellow/orange)", c.colorblind) { v ->
            update { it.copy(colorblind = v) }
        }

        Spacer(Modifier.height(16.dp))
        Text("Advanced", fontWeight = FontWeight.Bold)
        Text(
            "Automations on each new trip offer.",
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            fontSize = 13.sp,
        )
        Spacer(Modifier.height(4.dp))
        ToggleRow("Notification with map shortcuts", c.notificationEnabled) { v ->
            update { it.copy(notificationEnabled = v) }
        }
        ToggleRow("Voice announcement (reads the offer aloud)", c.voiceEnabled) { v ->
            update { it.copy(voiceEnabled = v) }
        }
        ToggleRow("Auto-save a screenshot to your gallery", c.screenshotEnabled) { v ->
            update { it.copy(screenshotEnabled = v) }
        }
    }
}

@Composable
private fun IntSlider(
    title: String,
    value: Int,
    min: Int,
    max: Int,
    suffix: String,
    onChange: (Int) -> Unit,
) {
    Text("$title: $value$suffix", fontWeight = FontWeight.Bold)
    Slider(
        value = value.coerceIn(min, max).toFloat(),
        onValueChange = { onChange(it.toInt().coerceIn(min, max)) },
        valueRange = min.toFloat()..max.toFloat(),
    )
    Spacer(Modifier.height(8.dp))
}

@Composable
private fun ToggleRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = onChange)
    }
}

private fun String.titlecase(): String =
    lowercase().replaceFirstChar { it.uppercase() }
