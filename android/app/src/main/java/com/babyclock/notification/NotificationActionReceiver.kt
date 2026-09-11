package com.babyclock.notification

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat
import androidx.glance.appwidget.updateAll
import com.babyclock.data.EventRepository
import com.babyclock.data.EventType
import com.babyclock.data.RecordSource
import com.babyclock.ui.Format
import com.babyclock.widget.BabyClockWidget
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * 通知 action 落地接收器（PRD §3.9）。
 *
 * 锁屏点击通知按钮 → 此接收器在后台写 Room（来源 NOTIFICATION）→ 刷新通知 + Glance 小组件，
 * 全程不打开 App UI（§3.9 规则 6）。纯离线，不联网。
 *
 * 奶粉特殊处理（§3.9 规则 5）：沿用上次毫升数直接写入并给出 5s 撤销窗口；
 * 无历史档位时由服务侧改用 activity PendingIntent 直接开面板，不会走到这里。
 */
class NotificationActionReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        val recordId = intent.getStringExtra(RecordNotificationService.EXTRA_RECORD_ID)
        val appContext = context.applicationContext
        val pendingResult = goAsync()
        CoroutineScope(Dispatchers.IO).launch {
            try {
                handle(appContext, action, recordId)
            } finally {
                pendingResult.finish()
            }
        }
    }

    private suspend fun handle(context: Context, action: String, recordId: String?) {
        EventRepository.init(context)
        when (action) {
            RecordNotificationService.ACTION_RECORD_BREAST -> {
                EventRepository.submit(EventType.FEED, RecordSource.NOTIFICATION)
                afterWrite(context)
            }
            RecordNotificationService.ACTION_RECORD_SLEEP -> {
                EventRepository.submit(EventType.SLEEP, RecordSource.NOTIFICATION)
                afterWrite(context)
            }
            RecordNotificationService.ACTION_RECORD_MEDICINE -> {
                EventRepository.submit(EventType.MEDICINE, RecordSource.NOTIFICATION)
                afterWrite(context)
            }
            RecordNotificationService.ACTION_RECORD_POOP -> {
                EventRepository.submit(EventType.POOP, RecordSource.NOTIFICATION)
                afterWrite(context)
            }
            RecordNotificationService.ACTION_RECORD_FORMULA -> handleFormula(context)
            RecordNotificationService.ACTION_UNDO -> handleUndo(context, recordId)
            // 通知被划掉（Android 14+ 可划掉前台服务通知）：5s 后重建，不做高频重试（§3.9 异常处理）。
            RecordNotificationService.ACTION_DISMISSED -> {
                delay(RecordNotificationService.UNDO_WINDOW_MS)
                RecordNotificationService.refreshNow(context)
            }
        }
    }

    private suspend fun handleFormula(context: Context) {
        val lastMl = EventRepository.allEvents()
            .filter { Format.isFormula(it) }
            .maxByOrNull { it.startAt }
            ?.volumeMl
        if (lastMl == null || lastMl <= 0) {
            // 理论上服务侧已用 activity PI 拦截无历史的情况；兜底刷新通知即可，不写半条记录。
            RecordNotificationService.refreshNow(context)
            return
        }
        val e = EventRepository.submitFormula(lastMl, RecordSource.NOTIFICATION)
        afterWrite(context)
        val si = Intent(context, RecordNotificationService::class.java)
            .setAction(RecordNotificationService.ACTION_SHOW_UNDO)
            .putExtra(RecordNotificationService.EXTRA_RECORD_ID, e.id)
            .putExtra(RecordNotificationService.EXTRA_ML, lastMl)
        ContextCompat.startForegroundService(context, si)
    }

    private suspend fun handleUndo(context: Context, recordId: String?) {
        if (recordId == null) return
        val target = EventRepository.allEvents().firstOrNull { it.id == recordId }
        if (target != null) EventRepository.delete(target)
        afterWrite(context)
    }

    /** 写入后：刷新通知内容 + 触发 Glance 小组件更新（§3.9 规则 6）。 */
    private suspend fun afterWrite(context: Context) {
        RecordNotificationService.refreshNow(context)
        BabyClockWidget().updateAll(context)
    }
}
