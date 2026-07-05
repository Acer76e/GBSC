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
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.gbsc.cherry.data.ProfitConfig
import com.gbsc.cherry.data.Repo
import com.gbsc.cherry.ui.theme.BadRed
import com.gbsc.cherry.ui.theme.BrandOrange
import com.gbsc.cherry.ui.theme.GoodGreen
import java.util.Locale

@Composable
fun ProfitScreen(modifier: Modifier = Modifier) {
    val settings by Repo.settings.collectAsState()
    val p = settings.profit

    var earnings by remember { mutableStateOf(numStr(p.monthlyEarnings)) }
    var miles by remember { mutableStateOf(numStr(p.monthlyMiles)) }
    var hours by remember { mutableStateOf(numStr(p.monthlyHours)) }
    var financing by remember { mutableStateOf(numStr(p.financing)) }
    var fuel by remember { mutableStateOf(numStr(p.fuel)) }
    var insurance by remember { mutableStateOf(numStr(p.insurance)) }
    var maintenance by remember { mutableStateOf(numStr(p.maintenance)) }
    var phone by remember { mutableStateOf(numStr(p.phone)) }
    var other by remember { mutableStateOf(numStr(p.other)) }
    var note by remember { mutableStateOf("") }

    val cfg = ProfitConfig(
        monthlyEarnings = earnings.d(),
        monthlyMiles = miles.d(),
        monthlyHours = hours.d(),
        financing = financing.d(),
        fuel = fuel.d(),
        insurance = insurance.d(),
        maintenance = maintenance.d(),
        phone = phone.d(),
        other = other.d(),
    )

    Column(
        modifier = modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(20.dp)
    ) {
        Text("Net Profit", fontSize = 26.sp, fontWeight = FontWeight.Bold)
        Text(
            "Figures are monthly. Cost per mile feeds the live trip profit on the card.",
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(16.dp))

        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp)) {
                Text("Monthly Net Profit", fontWeight = FontWeight.Bold)
                Text(
                    "$" + money(cfg.netProfit) + "  (" + pct(cfg.netMargin) + ")",
                    fontSize = 28.sp,
                    fontWeight = FontWeight.Bold,
                    color = if (cfg.netProfit >= 0) GoodGreen else BadRed,
                )
                Spacer(Modifier.height(12.dp))
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Metric("Earn / mile", "$" + money(cfg.earningsPerMile))
                    Metric("Cost / mile", "$" + money(cfg.costPerMile))
                }
                Spacer(Modifier.height(8.dp))
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Metric("Earn / hour", "$" + money(cfg.earningsPerHour))
                    Metric("Cost / hour", "$" + money(cfg.costPerHour))
                }
                Spacer(Modifier.height(4.dp))
                Text(
                    "Monthly costs: $" + money(cfg.totalCosts),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }

        Spacer(Modifier.height(16.dp))
        Text("Income", fontWeight = FontWeight.Bold)
        NumberField("Gross earnings / month", earnings) { earnings = it }
        NumberField("Miles driven / month", miles) { miles = it }
        NumberField("Hours worked / month", hours) { hours = it }

        Spacer(Modifier.height(12.dp))
        Text("Monthly costs", fontWeight = FontWeight.Bold)
        NumberField("Financing / lease", financing) { financing = it }
        NumberField("Fuel", fuel) { fuel = it }
        NumberField("Insurance", insurance) { insurance = it }
        NumberField("Maintenance", maintenance) { maintenance = it }
        NumberField("Phone / data", phone) { phone = it }
        NumberField("Other", other) { other = it }

        Spacer(Modifier.height(16.dp))
        Button(
            onClick = {
                Repo.updateSettings { it.copy(profit = cfg) }
                note = "Saved."
            },
            modifier = Modifier.fillMaxWidth(),
            colors = ButtonDefaults.buttonColors(containerColor = BrandOrange),
        ) { Text("Save") }

        Spacer(Modifier.height(8.dp))
        OutlinedButton(
            onClick = {
                Repo.updateSettings {
                    it.copy(
                        profit = cfg,
                        filters = it.filters.copy(
                            miGood = round2(cfg.earningsPerMile),
                            miBad = round2(cfg.costPerMile),
                            hrGood = round2(cfg.earningsPerHour),
                            hrBad = round2(cfg.costPerHour),
                        )
                    )
                }
                note = "Applied $/mi and $/hr to your Trip Filters."
            },
            modifier = Modifier.fillMaxWidth(),
        ) { Text("Apply \$/mi and \$/hr to Trip Filters") }

        if (note.isNotEmpty()) {
            Spacer(Modifier.height(8.dp))
            Text(note, color = GoodGreen)
        }
    }
}

@Composable
private fun Metric(label: String, value: String) {
    Column {
        Text(label, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, fontWeight = FontWeight.Bold, fontSize = 16.sp)
    }
}

@Composable
private fun NumberField(label: String, value: String, onChange: (String) -> Unit) {
    OutlinedTextField(
        value = value,
        onValueChange = { onChange(sanitizeDecimal(it)) },
        label = { Text(label) },
        singleLine = true,
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
    )
}

/** Keeps digits plus a single decimal separator. Decimal keyboards emit ',' in
 *  comma-decimal locales — accept it and normalize to '.' so "312,50" parses as
 *  312.50 (not 31250). US input with '.' is unchanged. */
private fun sanitizeDecimal(raw: String): String {
    val sb = StringBuilder()
    var seenSeparator = false
    for (c in raw) {
        when {
            c.isDigit() -> sb.append(c)
            (c == '.' || c == ',') && !seenSeparator -> {
                sb.append('.')
                seenSeparator = true
            }
        }
    }
    return sb.toString()
}

private fun String.d(): Double = toDoubleOrNull() ?: 0.0
private fun money(v: Double): String = String.format(Locale.US, "%,.2f", v)
private fun pct(v: Double): String = String.format(Locale.US, "%.1f%%", v)
private fun round2(v: Double): Double = Math.round(v * 100.0) / 100.0
private fun numStr(v: Double): String =
    if (v == v.toLong().toDouble()) v.toLong().toString() else v.toString()
