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
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RangeSlider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.gbsc.cherry.data.Repo
import com.gbsc.cherry.ui.theme.BadRed
import com.gbsc.cherry.ui.theme.GoodGreen
import java.util.Locale
import kotlin.math.roundToInt

@Composable
fun FiltersScreen(modifier: Modifier = Modifier) {
    val settings by Repo.settings.collectAsState()
    val f = settings.filters

    Column(
        modifier = modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(20.dp)
    ) {
        Text("Cherry Picker", fontSize = 26.sp, fontWeight = FontWeight.Bold)
        Text(
            "Set your goals to color-rate trip offers. Red = bad, Yellow = ok, Green = good.",
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(16.dp))

        GoalSlider("Earnings per Mile", "$", f.miBad, f.miGood, 0f..6f, 2) { bad, good ->
            Repo.updateSettings { it.copy(filters = it.filters.copy(miBad = bad, miGood = good)) }
        }
        GoalSlider("Earnings per Hour", "$", f.hrBad, f.hrGood, 0f..120f, 0) { bad, good ->
            Repo.updateSettings { it.copy(filters = it.filters.copy(hrBad = bad, hrGood = good)) }
        }
        GoalSlider("Earnings per Minute", "$", f.minBad, f.minGood, 0f..3f, 2) { bad, good ->
            Repo.updateSettings { it.copy(filters = it.filters.copy(minBad = bad, minGood = good)) }
        }
        GoalSlider("Passenger Rating", "", f.ratingBad, f.ratingGood, 3f..5f, 2) { bad, good ->
            Repo.updateSettings { it.copy(filters = it.filters.copy(ratingBad = bad, ratingGood = good)) }
        }
    }
}

@Composable
private fun GoalSlider(
    title: String,
    unit: String,
    bad: Double,
    good: Double,
    range: ClosedFloatingPointRange<Float>,
    decimals: Int,
    onChange: (bad: Double, good: Double) -> Unit,
) {
    Card(Modifier.fillMaxWidth().padding(vertical = 8.dp)) {
        Column(Modifier.padding(16.dp)) {
            Text(title, fontWeight = FontWeight.Bold, fontSize = 16.sp)
            Spacer(Modifier.height(4.dp))
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text("Bad ≤ $unit${fmt(bad, decimals)}", color = BadRed, fontWeight = FontWeight.Bold)
                Text("Good ≥ $unit${fmt(good, decimals)}", color = GoodGreen, fontWeight = FontWeight.Bold)
            }
            val start = bad.toFloat().coerceIn(range.start, range.endInclusive)
            val end = good.toFloat().coerceIn(start, range.endInclusive)
            RangeSlider(
                value = start..end,
                onValueChange = { r ->
                    onChange(round(r.start, decimals), round(r.endInclusive, decimals))
                },
                valueRange = range,
                colors = SliderDefaults.colors(
                    activeTrackColor = GoodGreen,
                    inactiveTrackColor = BadRed.copy(alpha = 0.5f),
                ),
            )
        }
    }
}

private fun fmt(v: Double, decimals: Int): String =
    String.format(Locale.US, "%.${decimals}f", v)

private fun round(v: Float, decimals: Int): Double {
    val factor = Math.pow(10.0, decimals.toDouble())
    return (v * factor).roundToInt() / factor
}
