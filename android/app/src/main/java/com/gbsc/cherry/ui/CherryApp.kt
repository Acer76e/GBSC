package com.gbsc.cherry.ui

import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Calculate
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import com.gbsc.cherry.ui.screens.FiltersScreen
import com.gbsc.cherry.ui.screens.HistoryScreen
import com.gbsc.cherry.ui.screens.HomeScreen
import com.gbsc.cherry.ui.screens.ProfitScreen
import com.gbsc.cherry.ui.screens.SettingsScreen

private enum class Tab(val label: String, val icon: ImageVector) {
    HOME("Home", Icons.Filled.Home),
    FILTERS("Filters", Icons.Filled.Tune),
    PROFIT("Profit", Icons.Filled.Calculate),
    HISTORY("History", Icons.Filled.History),
    SETTINGS("Card", Icons.Filled.BarChart),
}

@Composable
fun CherryApp(
    onStart: () -> Unit,
    onStop: () -> Unit,
    onTestOffer: () -> Unit,
    hasOverlayPermission: () -> Boolean,
    isAccessibilityEnabled: () -> Boolean,
    openAccessibilitySettings: () -> Unit,
) {
    var selected by remember { mutableIntStateOf(0) }
    val tabs = Tab.entries

    Scaffold(
        bottomBar = {
            NavigationBar {
                tabs.forEachIndexed { index, tab ->
                    NavigationBarItem(
                        selected = selected == index,
                        onClick = { selected = index },
                        icon = { Icon(tab.icon, contentDescription = tab.label) },
                        label = { Text(tab.label) },
                    )
                }
            }
        }
    ) { padding ->
        val modifier = Modifier.padding(padding)
        when (tabs[selected]) {
            Tab.HOME -> HomeScreen(
                modifier, onStart, onStop, onTestOffer, hasOverlayPermission,
                isAccessibilityEnabled, openAccessibilitySettings
            )
            Tab.FILTERS -> FiltersScreen(modifier)
            Tab.PROFIT -> ProfitScreen(modifier)
            Tab.HISTORY -> HistoryScreen(modifier)
            Tab.SETTINGS -> SettingsScreen(modifier)
        }
    }
}
