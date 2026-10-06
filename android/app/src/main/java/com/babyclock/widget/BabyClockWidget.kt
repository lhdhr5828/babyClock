package com.babyclock.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.LocalSize
import androidx.glance.action.ActionParameters
import androidx.glance.action.actionParametersOf
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
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
 * 桌面小组件（PRD §3.5，Android 侧 P1）：一键记录 + 显示当前状态，纯离线。
 * 写入经 ActionCallback 在后台走同一 EventRepository 状态机（来源 WIDGET）。
 *
 * 尺寸差异（§3.5 规则 2 / 规则 5，与 iOS 小组件一致）：
 *   小尺寸（宽 < 240dp）—— 状态 + 母乳/睡觉/吃药/排便四键 2×2，**不含奶粉入口**
 *   中尺寸（宽 ≥ 240dp）—— 上述四键横排 + 内联三档毫升（60/90/120），点一下即写入，不弹面板
 * 奶粉键位缺失是有意的：小尺寸放不下三档，误记毫升比少一个入口更糟。
 *
 * sizeMode 必须是 Exact，这是这块最容易踩空的地方：Glance 默认 SizeMode.Single，
 * 此时 LocalSize 只回传 widget_info.xml 的 minWidth/minHeight，跟用户实际拖出的格子无关，
 * 上面的 240dp 分支永远进不去。Exact 在 API 31+ 才读宿主 option（宽=当前宽、高=最大高），
 * 31 以下退回 Single 行为 —— 老系统上恒定走小尺寸 2×2，少一个入口，不会裁内容。
 *
 * minHeight 150dp 与"三段式"内容是耦合的：RemoteViews 超出宿主尺寸的部分直接裁掉
 * （不滚动也不压缩），改字号或内边距要同步 widget_info.xml 那个数。
 */
class BabyClockWidget : GlanceAppWidget() {
    override val sizeMode = SizeMode.Exact

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        EventRepository.init(context)
        val now = System.currentTimeMillis()
        val ongoing = EventRepository.ongoing()
        // §3.5 规则 6：距上次喂奶 = 母乳/奶粉更近的一次开始时刻
        val lastFeedAt = EventRepository.lastOccurrence(EventType.FEED)
        provideContent { WidgetContent(now, ongoing, lastFeedAt) }
    }

    @Composable
    private fun WidgetContent(now: Long, ongoing: BabyEvent?, lastFeedAt: Long?) {
        val size = LocalSize.current
        // 宽度够才横排四键 + 三档；窄尺寸改 2×2，保证每键点击区不小于 48dp（§3.5 异常表）。
        // 高度方向不设门槛：Exact 给的是宿主允许的最大高，而 minHeight 已保证三段放得下。
        val singleRow = size.width >= 240.dp
        val status = if (ongoing != null)
            "${ongoing.type.title}进行中 · ${Format.hms(now - ongoing.startAt)}"
        else
            "当前无进行中 · " +
                (lastFeedAt?.let { "上次喂奶 ${Format.clock(it)}" } ?: "尚无喂奶记录")

        Column(
            modifier = GlanceModifier.fillMaxSize()
                .background(ColorProvider(day = Day, night = Night))
                .padding(8.dp)
        ) {
            Text(
                text = status,
                maxLines = 1,
                style = TextStyle(
                    color = ColorProvider(day = Text1, night = Text1Night),
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Bold
                )
            )
            Spacer(GlanceModifier.height(6.dp))
            if (singleRow) {
                KeyRow(widgetKeys)
            } else {
                widgetKeys.chunked(2).forEachIndexed { i, row ->
                    if (i > 0) Spacer(GlanceModifier.height(4.dp))
                    KeyRow(row)
                }
            }
            if (singleRow) {
                Spacer(GlanceModifier.height(8.dp))
                Row(
                    modifier = GlanceModifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("🍼", style = TextStyle(fontSize = 12.sp))
                    Spacer(GlanceModifier.width(6.dp))
                    formulaTiers.forEachIndexed { i, ml ->
                        if (i > 0) Spacer(GlanceModifier.width(6.dp))
                        TierButton(ml, GlanceModifier.defaultWeight())
                    }
                }
            }
        }
    }

    @Composable
    private fun KeyRow(keys: List<WidgetKey>) {
        Row(modifier = GlanceModifier.fillMaxWidth()) {
            keys.forEachIndexed { i, key ->
                if (i > 0) Spacer(GlanceModifier.width(6.dp))
                WidgetButton(key, GlanceModifier.defaultWeight())
            }
        }
    }

    // Glance 的 Column 没有 verticalArrangement，只能靠 padding 撑出内在高度；
    // 因此这里的 padding 数字直接决定 minHeight 需要多高，改字号/内边距要同步 widget_info.xml。
    @Composable
    private fun WidgetButton(key: WidgetKey, modifier: GlanceModifier) {
        Column(
            modifier = modifier
                .background(ColorProvider(day = Card, night = CardNight))
                .padding(vertical = 8.dp)
                .clickable(
                    actionRunCallback<RecordActionReceiver>(
                        parameters = actionParametersOf(TYPE_KEY to key.type.name)
                    )
                ),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(key.emoji, style = TextStyle(fontSize = 16.sp))
            Text(
                key.label,
                style = TextStyle(
                    color = ColorProvider(day = Text2, night = Text2Night),
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Medium
                )
            )
        }
    }

    @Composable
    private fun TierButton(ml: Int, modifier: GlanceModifier) {
        Column(
            modifier = modifier
                .background(ColorProvider(day = Tier, night = TierNight))
                .padding(vertical = 7.dp)
                .clickable(
                    actionRunCallback<RecordFormulaActionReceiver>(
                        parameters = actionParametersOf(VOLUME_KEY to ml)
                    )
                ),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                "${ml}ml",
                style = TextStyle(
                    color = ColorProvider(day = TierText, night = TierTextNight),
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold
                )
            )
        }
    }
}

/** 小组件四键（§3.5 规则 2）：吃奶键即母乳，奶粉走下方三档，小尺寸不含奶粉入口。 */
private data class WidgetKey(val type: EventType, val emoji: String, val label: String)

private val widgetKeys = listOf(
    WidgetKey(EventType.FEED, "🤱", "母乳"),
    WidgetKey(EventType.SLEEP, "😴", "睡觉"),
    WidgetKey(EventType.MEDICINE, "💊", "吃药"),
    WidgetKey(EventType.POOP, "🧷", "排便")
)

private val formulaTiers = listOf(60, 90, 120)

private val TYPE_KEY = ActionParameters.Key<String>("event_type")
private val VOLUME_KEY = ActionParameters.Key<Int>("volume_ml")

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

/** 奶粉档位直点：等同 App 内选档，写入零时长 FEED/FORMULA 段并打断进行中段。 */
class RecordFormulaActionReceiver : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        val ml = parameters[VOLUME_KEY] ?: return
        if (ml <= 0) return
        EventRepository.init(context)
        EventRepository.submitFormula(ml, RecordSource.WIDGET)
        BabyClockWidget().updateAll(context)
    }
}

class BabyClockWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = BabyClockWidget()
}

// 明暗两套底色：小组件铺在桌面上，深色模式下不能用白底。
private val Day = Color(0xFFFFF8F1)
private val Night = Color(0xFF2A211B)
private val Card = Color(0xFFFFFFFF)
private val CardNight = Color(0xFF3A2E26)
private val Tier = Color(0xFFFFD9C4)
private val TierNight = Color(0xFF4A3325)
private val Text1 = Color(0xFF4A3728)
private val Text1Night = Color(0xFFF2E7DE)
private val Text2 = Color(0xFF8C7362)
private val Text2Night = Color(0xFFC9B4A5)
private val TierText = Color(0xFFF2703F)
private val TierTextNight = Color(0xFFFFB74D)
