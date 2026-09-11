package com.babyclock.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import com.babyclock.data.EventType

// 暖色调，映射 design/design-tokens.json
object Warm {
    val Bg = Color(0xFFFFF8F1)
    val Elevated = Color(0xFFFFFFFF)
    val Sunken = Color(0xFFFBEDE0)
    val Primary = Color(0xFFFF8A5C)
    val PrimaryStrong = Color(0xFFF2703F)
    val PrimarySoft = Color(0xFFFFD9C4)
    val Text1 = Color(0xFF4A3728)
    val Text2 = Color(0xFF8C7362)
    val Text3 = Color(0xFFB79E8C)
    val Hairline = Color(0xFFF0E0D2)

    fun fill(t: EventType) = when (t) {
        EventType.FEED -> Color(0xFFFFB74D)
        EventType.SLEEP -> Color(0xFFF2A6A0)
        EventType.MEDICINE -> Color(0xFFFF8A80)
        EventType.POOP -> Color(0xFFC9A227)
    }
    fun soft(t: EventType) = when (t) {
        EventType.FEED -> Color(0xFFFFE9C7)
        EventType.SLEEP -> Color(0xFFFBE0DD)
        EventType.MEDICINE -> Color(0xFFFFDDD9)
        EventType.POOP -> Color(0xFFF2EBCB)
    }
}

private val WarmColorScheme = lightColorScheme(
    primary = Warm.PrimaryStrong,
    onPrimary = Color.White,
    primaryContainer = Warm.PrimarySoft,
    secondary = Warm.Primary,
    background = Warm.Bg,
    onBackground = Warm.Text1,
    surface = Warm.Elevated,
    onSurface = Warm.Text1,
    surfaceVariant = Warm.Sunken,
    onSurfaceVariant = Warm.Text2,
    outline = Warm.Hairline
)

@Composable
fun BabyClockTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = WarmColorScheme, typography = WarmTypography, content = content)
}
