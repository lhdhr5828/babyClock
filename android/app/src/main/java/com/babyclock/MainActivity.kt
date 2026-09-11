package com.babyclock

import android.Manifest
import android.app.Application
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.babyclock.data.EventRepository
import com.babyclock.data.RecordSource
import com.babyclock.notification.RecordNotificationService
import com.babyclock.ui.*
import com.babyclock.ui.theme.BabyClockTheme
import kotlinx.coroutines.launch

class BabyClockApp : Application() {
    override fun onCreate() {
        super.onCreate()
        // 纯离线初始化：仅打开本地 Room(SQLite) 数据库，不发起任何网络请求
        EventRepository.init(this)
    }
}

class MainActivity : ComponentActivity() {

    // 通知权限申请（Android 13+）。拒绝则降级：不启动通知服务，桌面小组件 + App 内记录仍可用（AC-20）。
    private val notificationPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            if (granted) RecordNotificationService.start(this)
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 来自 App Shortcuts（桌面长按图标）的快捷记录意图
        handleShortcutIntent(intent?.action)
        // 锁屏常驻通知入口（PRD §3.9）：申请权限并启动前台服务
        ensureNotificationEntry()
        val openFormula =
            intent?.getBooleanExtra(RecordNotificationService.EXTRA_OPEN_FORMULA, false) ?: false
        setContent {
            BabyClockTheme {
                RootScreen(openFormula = openFormula)
            }
        }
    }

    override fun onResume() {
        super.onResume()
        // 回到前台时刷新通知（若被 ROM 杀掉则借此重建，§3.9 异常处理）。权限被拒时不启动服务。
        if (NotificationManagerCompat.from(this).areNotificationsEnabled()) {
            RecordNotificationService.refreshNow(this)
        }
    }

    private fun ensureNotificationEntry() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val granted = ContextCompat.checkSelfPermission(
                this, Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
            if (granted) RecordNotificationService.start(this)
            else notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            // API 26–32：通知默认允许（用户可在系统设置关闭），直接启动。
            RecordNotificationService.start(this)
        }
    }

    private fun handleShortcutIntent(action: String?) {
        val type = action?.removePrefix("com.babyclock.action.RECORD_")?.let {
            runCatching { com.babyclock.data.EventType.valueOf(it) }.getOrNull()
        } ?: return
        // Android App Shortcuts 通过桌面长按图标拉起 MainActivity，属于应用内入口；
        // Android 无系统语音通道，故来源标记为 APP 而非 VOICE（VOICE 仅 iOS）。
        lifecycleScope.launch { EventRepository.submit(type, RecordSource.APP) }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RootScreen(openFormula: Boolean = false) {
    val vm: RecorderViewModel = viewModel()
    LaunchedEffect(Unit) { vm.reload() }
    var tab by remember { mutableIntStateOf(0) }

    Scaffold(
        modifier = Modifier.fillMaxSize(),
        bottomBar = {
            NavigationBar(containerColor = MaterialTheme.colorScheme.surface) {
                NavigationBarItem(selected = tab == 0, onClick = { tab = 0 },
                    icon = { Text("🏠") }, label = { Text("记录") })
                NavigationBarItem(selected = tab == 1, onClick = { tab = 1 },
                    icon = { Text("🗓") }, label = { Text("时间轴") })
                NavigationBarItem(selected = tab == 2, onClick = { tab = 2 },
                    icon = { Text("📊") }, label = { Text("统计") })
            }
        }
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            when (tab) {
                0 -> HomeScreen(vm, onOpenTimeline = { tab = 1 }, initialFormula = openFormula)
                1 -> TimelineScreen(vm)
                2 -> StatsScreen(vm)
            }
        }
    }
}
