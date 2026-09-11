package com.babyclock.notification

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.babyclock.MainActivity
import com.babyclock.R
import com.babyclock.data.BabyEvent
import com.babyclock.data.EventRepository
import com.babyclock.data.EventType
import com.babyclock.data.FeedMethod
import com.babyclock.ui.Format
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * 锁屏常驻通知一键记录服务（PRD §3.9，Android P0）。
 *
 * 这是 Android 端「不解锁记录」的唯一可靠路径：Android 自 5.0 起无锁屏小组件，
 * 第三方语音通道（Conversational Actions）已于 2023-06-13 关停。
 *
 * 设计红线：
 * - 通知是「记录入口」而非「提醒」——低优先级、静音、无震动、无声音、不弹横幅（§3.4 范围边界）。
 * - action 不设 setAuthenticationRequired，保证锁屏可直接点击（§3.9 规则 7）。
 * - 纯离线：仅写本机 Room，不发起任何网络请求。
 *
 * 保活：foregroundServiceType=specialUse（Android 14+ 用户可划掉普通 ongoing 通知，
 * 前台服务 + 删除后 5s 重建保证常驻，§3.9 权限与保活表）。
 */
class RecordNotificationService : Service() {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var ticker: Job? = null

    /** 奶粉撤销瞬态：5s 内通知顶部显示「已记录 Nml · 撤销」。 */
    private var pendingUndo: Undo? = null

    private data class Undo(val recordId: String, val ml: Int)

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // 必须尽快进入前台（startForegroundService 后 5s 内），先用占位内容，随后 refresh() 覆盖为真实数据。
        enterForeground(buildNotification(ongoing = null, now = System.currentTimeMillis(), lastFeed = null, lastFormulaMl = null))

        when (intent?.action) {
            ACTION_STOP -> {
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_SHOW_UNDO -> {
                val id = intent.getStringExtra(EXTRA_RECORD_ID)
                val ml = intent.getIntExtra(EXTRA_ML, 0)
                if (id != null && ml > 0) showUndo(id, ml)
            }
            // ACTION_START / ACTION_REFRESH / null：均触发一次刷新
        }

        scope.launch { refresh() }
        ensureTicker()
        return START_STICKY
    }

    override fun onDestroy() {
        ticker?.cancel()
        scope.cancel()
        super.onDestroy()
    }

    private fun ensureTicker() {
        if (ticker?.isActive == true) return
        ticker = scope.launch {
            while (true) {
                delay(REFRESH_INTERVAL_MS)
                refresh()
            }
        }
    }

    private fun showUndo(recordId: String, ml: Int) {
        pendingUndo = Undo(recordId, ml)
        scope.launch {
            delay(UNDO_WINDOW_MS)
            if (pendingUndo?.recordId == recordId) {
                pendingUndo = null
                refresh()
            }
        }
    }

    private suspend fun refresh() {
        // 权限被拒时静默跳过（AC-20 降级：不崩溃、不反复弹窗）。
        if (!NotificationManagerCompat.from(this).areNotificationsEnabled()) return
        EventRepository.init(this)
        val now = System.currentTimeMillis()
        val ongoing = EventRepository.ongoing()
        val feeds = EventRepository.allEvents().filter { it.type == EventType.FEED }
        val lastFeed = feeds.maxByOrNull { it.startAt }
        val lastFormulaMl = feeds.filter { Format.isFormula(it) }.maxByOrNull { it.startAt }?.volumeMl
        NotificationManagerCompat.from(this)
            .notify(NOTIFICATION_ID, buildNotification(ongoing, now, lastFeed, lastFormulaMl))
    }

    private fun enterForeground(notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID, notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun createChannel() {
        val nm = getSystemService(NotificationManager::class.java) ?: return
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID, "锁屏快捷记录", NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "常驻通知，锁屏一键记录宝宝事件，不发出声音或提醒"
            enableVibration(false)
            enableLights(false)
            setShowBadge(false)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        nm.createNotificationChannel(channel)
    }

    private fun buildNotification(
        ongoing: BabyEvent?, now: Long, lastFeed: BabyEvent?, lastFormulaMl: Int?
    ): Notification {
        val undo = pendingUndo
        val title = when {
            undo != null -> "已记录 ${undo.ml}ml 奶粉"
            ongoing != null -> "${Format.label(ongoing)}中 · ${Format.hms(now - ongoing.startAt)}"
            else -> "宝宝记录"
        }
        val subtitle = when {
            undo != null -> "5 秒内可点「撤销」取消这条记录"
            else -> lastFeedLine(lastFeed, now)
        }

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(subtitle)
            .setStyle(NotificationCompat.BigTextStyle().bigText(subtitle))
            .setOngoing(true)
            .setSilent(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(openAppIntent())
            .setDeleteIntent(broadcastIntent(ACTION_DISMISSED, REQ_DISMISSED))

        if (undo != null) {
            builder.addAction(android.R.drawable.ic_menu_revert, "撤销", undoIntent(undo.recordId))
        }

        // 顺序即折叠态优先级：母乳 / 睡觉 / 奶粉 为折叠态前 3 个可见按钮（§3.9 规则 3），
        // 展开态再追加 吃药 / 排便，共 5 个。进行中事件的 action 文案动态变为「结束…」（§3.9 规则 4）。
        builder.addAction(R.drawable.ic_feed, breastLabel(ongoing), broadcastIntent(ACTION_RECORD_BREAST, REQ_BREAST))
        builder.addAction(R.drawable.ic_sleep, sleepLabel(ongoing), broadcastIntent(ACTION_RECORD_SLEEP, REQ_SLEEP))
        // 奶粉：有历史档位 → 广播沿用上次毫升数 + 撤销；无历史 → 直接开 App 面板（activity PI 不受后台启动限制）。
        val formulaPi = if (lastFormulaMl != null && lastFormulaMl > 0)
            broadcastIntent(ACTION_RECORD_FORMULA, REQ_FORMULA)
        else
            openFormulaActivityIntent()
        builder.addAction(R.drawable.ic_feed, "奶粉", formulaPi)
        builder.addAction(R.drawable.ic_medicine, "吃药", broadcastIntent(ACTION_RECORD_MEDICINE, REQ_MEDICINE))
        builder.addAction(R.drawable.ic_poop, "排便", broadcastIntent(ACTION_RECORD_POOP, REQ_POOP))

        return builder.build()
    }

    private fun breastLabel(ongoing: BabyEvent?): String =
        if (ongoing != null && ongoing.type == EventType.FEED && ongoing.feedMethod == FeedMethod.BREAST) "结束母乳" else "母乳"

    private fun sleepLabel(ongoing: BabyEvent?): String =
        if (ongoing != null && ongoing.type == EventType.SLEEP) "结束睡觉" else "睡觉"

    private fun lastFeedLine(lastFeed: BabyEvent?, now: Long): String {
        if (lastFeed == null) return "尚无喂奶记录 · 锁屏点按即可记录"
        val label = Format.label(lastFeed)
        val ml = if (Format.isFormula(lastFeed)) " ${lastFeed.volumeMl ?: 0}ml" else ""
        return "上次$label$ml · ${Format.relative(lastFeed.startAt, now)}"
    }

    private fun broadcastIntent(action: String, requestCode: Int): PendingIntent {
        val i = Intent(this, NotificationActionReceiver::class.java).setAction(action)
        return PendingIntent.getBroadcast(
            this, requestCode, i,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun undoIntent(recordId: String): PendingIntent {
        val i = Intent(this, NotificationActionReceiver::class.java)
            .setAction(ACTION_UNDO)
            .putExtra(EXTRA_RECORD_ID, recordId)
        return PendingIntent.getBroadcast(
            this, REQ_UNDO, i,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun openAppIntent(): PendingIntent {
        val i = Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return PendingIntent.getActivity(
            this, REQ_OPEN_APP, i,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    /** 无奶粉历史时，点「奶粉」直接打开 App 毫升面板（需解锁，§3.9 规则 5 的可接受降级）。 */
    private fun openFormulaActivityIntent(): PendingIntent {
        val i = Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            .putExtra(EXTRA_OPEN_FORMULA, true)
        return PendingIntent.getActivity(
            this, REQ_FORMULA_OPEN, i,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    companion object {
        const val CHANNEL_ID = "babyclock_record"
        const val NOTIFICATION_ID = 1001

        private const val REFRESH_INTERVAL_MS = 30_000L
        const val UNDO_WINDOW_MS = 5_000L

        // 服务自身指令
        const val ACTION_START = "com.babyclock.notif.START"
        const val ACTION_REFRESH = "com.babyclock.notif.REFRESH"
        const val ACTION_STOP = "com.babyclock.notif.STOP"
        const val ACTION_SHOW_UNDO = "com.babyclock.notif.SHOW_UNDO"

        // 广播 action（通知按钮 → NotificationActionReceiver）
        const val ACTION_RECORD_BREAST = "com.babyclock.notif.RECORD_BREAST"
        const val ACTION_RECORD_SLEEP = "com.babyclock.notif.RECORD_SLEEP"
        const val ACTION_RECORD_MEDICINE = "com.babyclock.notif.RECORD_MEDICINE"
        const val ACTION_RECORD_POOP = "com.babyclock.notif.RECORD_POOP"
        const val ACTION_RECORD_FORMULA = "com.babyclock.notif.RECORD_FORMULA"
        const val ACTION_UNDO = "com.babyclock.notif.UNDO"
        const val ACTION_DISMISSED = "com.babyclock.notif.DISMISSED"

        const val EXTRA_RECORD_ID = "record_id"
        const val EXTRA_ML = "ml"
        const val EXTRA_OPEN_FORMULA = "open_formula"

        // PendingIntent requestCode（彼此独立，避免复用覆盖）
        private const val REQ_BREAST = 1
        private const val REQ_SLEEP = 2
        private const val REQ_FORMULA = 3
        private const val REQ_MEDICINE = 4
        private const val REQ_POOP = 5
        private const val REQ_UNDO = 6
        private const val REQ_OPEN_APP = 7
        private const val REQ_DISMISSED = 8
        private const val REQ_FORMULA_OPEN = 9

        fun start(context: Context) {
            ContextCompat.startForegroundService(
                context, Intent(context, RecordNotificationService::class.java).setAction(ACTION_START)
            )
        }

        fun refreshNow(context: Context) {
            ContextCompat.startForegroundService(
                context, Intent(context, RecordNotificationService::class.java).setAction(ACTION_REFRESH)
            )
        }

        fun stop(context: Context) {
            context.startService(
                Intent(context, RecordNotificationService::class.java).setAction(ACTION_STOP)
            )
        }
    }
}
