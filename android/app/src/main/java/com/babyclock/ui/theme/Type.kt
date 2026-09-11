package com.babyclock.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

// 圆体优先，呼应 iOS squircle / SF Pro Rounded 风格
private val Rounded = FontFamily.Default

val WarmTypography = Typography(
    displaySmall = TextStyle(fontFamily = Rounded, fontWeight = FontWeight.Bold, fontSize = 40.sp, lineHeight = 44.sp),
    headlineMedium = TextStyle(fontFamily = Rounded, fontWeight = FontWeight.Bold, fontSize = 24.sp),
    titleLarge = TextStyle(fontFamily = Rounded, fontWeight = FontWeight.Bold, fontSize = 22.sp),
    titleMedium = TextStyle(fontFamily = Rounded, fontWeight = FontWeight.SemiBold, fontSize = 18.sp),
    bodyLarge = TextStyle(fontFamily = Rounded, fontWeight = FontWeight.Normal, fontSize = 16.sp),
    bodyMedium = TextStyle(fontFamily = Rounded, fontWeight = FontWeight.Normal, fontSize = 14.sp),
    labelLarge = TextStyle(fontFamily = Rounded, fontWeight = FontWeight.Bold, fontSize = 15.sp),
    labelMedium = TextStyle(fontFamily = Rounded, fontWeight = FontWeight.SemiBold, fontSize = 13.sp),
    labelSmall = TextStyle(fontFamily = Rounded, fontWeight = FontWeight.Medium, fontSize = 11.sp)
)
