package com.babyclock.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.action.ActionParameters
import androidx.glance.action.actionParametersOf
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.updateAll
import androidx.glance.background
import androidx.glance.color.ColorProvider
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import com.babyclock.data.*
import com.babyclock.ui.Format

/**
 * 桌面/锁屏小组件：不解锁一键记录四类事件 + 显示当前状态。
 * 写入通过 RecordActionReceiver 在后台走同一 EventRepository 状态机（来源 WIDGET），纯离线。
 */
class BabyClockWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        EventRepository.init(context)
        val now = System.currentTimeMillis()
        val ongoing = EventRepository.ongoing()
        provideContent { WidgetContent(now, ongoing) }
    }

    @Composable
    private fun WidgetContent(now: Long, ongoing: BabyEvent?) {
        Column(
            modifier = GlanceModifier.fillMaxSize()
                .background(ColorProvider(day = Color(0xFFFFF8F1), night = Color(0xFFFFF8F1)))
                .padding(12.dp)
        ) {
            Text(
                text = if (ongoing != null)
                    "${ongoing.type.title}进行中 · ${Format.hms(now - ongoing.startAt)}"
                else "当前无进行中",
                style = TextStyle(
                    color = ColorProvider(day = Color(0xFF4A3728), night = Color(0xFF4A3728)),
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Bold
                )
            )
            Spacer(GlanceModifier.height(10.dp))
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                EventType.values().forEachIndexed { i, type ->
                    if (i > 0) Spacer(GlanceModifier.width(8.dp))
                    WidgetButton(type)
                }
            }
        }
    }

    @Composable
    private fun WidgetButton(type: EventType) {
        Column(
            modifier = GlanceModifier
                .width(72.dp)
                .background(ColorProvider(day = Color(0xFFFFFFFF), night = Color(0xFFFFFFFF)))
                .padding(vertical = 10.dp)
                .clickable(
                    actionRunCallback<RecordActionReceiver>(
                        parameters = actionParametersOf(TYPE_KEY to type.name)
                    )
                ),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(Format.emoji(type), style = TextStyle(fontSize = 20.sp))
            Text(
                type.title,
                style = TextStyle(
                    color = ColorProvider(day = Color(0xFF8C7362), night = Color(0xFF8C7362)),
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Medium
                )
            )
        }
    }
}

private val TYPE_KEY = ActionParameters.Key<String>("event_type")

/** 后台写入接收器：执行状态机并刷新所有小组件。 */
class RecordActionReceiver : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        val typeName = parameters[TYPE_KEY] ?: return
        val type = runCatching { EventType.valueOf(typeName) }.getOrNull() ?: return
        EventRepository.init(context)
        EventRepository.submit(type, RecordSource.WIDGET)
        BabyClockWidget().updateAll(context)
    }
}

class BabyClockWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = BabyClockWidget()
}
