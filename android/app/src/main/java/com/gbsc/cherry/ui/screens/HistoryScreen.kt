package com.gbsc.cherry.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.DeleteSweep
import androidx.compose.material3.Card
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.gbsc.cherry.data.AppSettings
import com.gbsc.cherry.data.Grading
import com.gbsc.cherry.data.Repo
import com.gbsc.cherry.data.TripOffer
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@Composable
fun HistoryScreen(modifier: Modifier = Modifier) {
    val history by Repo.history.collectAsState()
    val settings by Repo.settings.collectAsState()

    Column(modifier = modifier.fillMaxSize()) {
        Row(
            Modifier.fillMaxWidth().padding(start = 20.dp, end = 8.dp, top = 16.dp, bottom = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f)) {
                Text("Trip Offers History", fontSize = 22.sp, fontWeight = FontWeight.Bold)
                Text(
                    "${history.size} records",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    fontSize = 13.sp,
                )
            }
            if (history.isNotEmpty()) {
                IconButton(onClick = { Repo.clearHistory() }) {
                    Icon(Icons.Filled.DeleteSweep, contentDescription = "Clear all")
                }
            }
        }

        if (history.isEmpty()) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text(
                    "No offers scanned yet.\nStart scanning and open Uber Driver.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        } else {
            LazyColumn(
                contentPadding = androidx.compose.foundation.layout.PaddingValues(
                    start = 16.dp, end = 16.dp, bottom = 16.dp
                ),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                items(history, key = { it.id }) { offer ->
                    OfferRow(offer, settings)
                }
            }
        }
    }
}

@Composable
private fun OfferRow(offer: TripOffer, settings: AppSettings) {
    val overall = Grading.overall(offer, settings.filters)
    val barColor = Color(Grading.color(overall))
    val profit = offer.fare - settings.profit.costPerMile * offer.totalMiles
    val profitPct = if (offer.fare > 0) (profit / offer.fare * 100).toInt() else 0

    Card(Modifier.fillMaxWidth()) {
        Column {
            Column(Modifier.padding(14.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(offer.app, fontWeight = FontWeight.Bold)
                        Text(
                            dateFmt.format(Date(offer.timestamp)),
                            fontSize = 12.sp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    IconButton(onClick = { Repo.deleteOffer(offer.id) }) {
                        Icon(Icons.Filled.Delete, contentDescription = "Delete")
                    }
                }
                Spacer(Modifier.height(4.dp))
                Row(verticalAlignment = Alignment.Bottom) {
                    Text(
                        "$" + money(offer.fare),
                        fontSize = 24.sp,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.weight(1f),
                    )
                    Stat("\$/mi", money(offer.perMile))
                    Spacer(Modifier.width(14.dp))
                    Stat("\$/hr", money(offer.perHour))
                    Spacer(Modifier.width(14.dp))
                    Stat("Rating", offer.rating?.let { money(it) } ?: "-")
                }
                Spacer(Modifier.height(8.dp))
                Text(
                    "Profit: $" + money(profit) + " (" + profitPct + "%)",
                    fontWeight = FontWeight.Bold,
                    color = barColor,
                    fontSize = 13.sp,
                )
            }
            Box(
                Modifier.fillMaxWidth().height(5.dp).background(barColor)
            )
            Column(Modifier.padding(14.dp)) {
                Text(
                    String.format(Locale.US, "%.1f mi · %d min", offer.totalMiles, offer.totalMinutes.toInt()),
                    fontWeight = FontWeight.Bold,
                    fontSize = 13.sp,
                )
                offer.pickupAddress?.let {
                    Spacer(Modifier.height(4.dp))
                    Text("● $it", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                offer.dropoffAddress?.let {
                    Text("■ $it", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

@Composable
private fun Stat(label: String, value: String) {
    Column(horizontalAlignment = Alignment.End) {
        Text(label, fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, fontWeight = FontWeight.Bold, fontSize = 14.sp)
    }
}

private fun money(v: Double): String = String.format(Locale.US, "%.2f", v)
private val dateFmt = SimpleDateFormat("MMM d · h:mma", Locale.US)
