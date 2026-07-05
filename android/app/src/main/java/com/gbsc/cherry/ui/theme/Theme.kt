package com.gbsc.cherry.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

val BrandOrange = Color(0xFFFF6D2E)
val GoodGreen = Color(0xFF22C55E)
val AvgYellow = Color(0xFFF5C518)
val BadRed = Color(0xFFEF4444)

private val LightColors = lightColorScheme(
    primary = BrandOrange,
    secondary = BrandOrange,
)

private val DarkColors = darkColorScheme(
    primary = BrandOrange,
    secondary = BrandOrange,
)

@Composable
fun CherryTheme(content: @Composable () -> Unit) {
    val colors = if (isSystemInDarkTheme()) DarkColors else LightColors
    MaterialTheme(colorScheme = colors, content = content)
}
