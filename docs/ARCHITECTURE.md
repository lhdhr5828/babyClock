# 技术方案与架构 · babyClock

**版本**：v1.1 ｜ **日期**：2026-09-11 ｜ 关联：`docs/PRD.md`（v1.1）、`shared/state-machine.md`、`design/design-tokens.json`

> **v1.1 修订要点**：① 事件表新增 `feed_method` / `volume_ml` / `breast_side`（母乳记时长、奶粉记毫升）；② 新增 `submitFormula` 零时长段入口；③ **修正 Android 快捷入口方案**——锁屏小组件与自定义语音在 Android 上均不可行，改押锁屏常驻通知；④ 修正 iOS 存储选型记录错误（实际为系统 `SQLite3`，非 GRDB）；⑤ 新增 24h 活动带可视化选型与 iOS 文件保护等级要求。

## 1. 框架选型（已确认）

| 维度 | 选择 | 理由 |
|------|------|------|
| 跨端策略 | **原生双端**：iOS = Swift，Android = Kotlin | 用户指定；快捷入口需深度集成系统能力，性能最好 |
| iOS UI | **SwiftUI**（iOS 16+） | 声明式、实时计时简洁、圆角/暖色还原度高 |
| iOS 存储 | **系统 `SQLite3` C API**（无第三方依赖） | 纯本地、零依赖、支持 App Group 共享容器。⚠️ v1.0 文档误记为 GRDB.swift，实际代码 `ios/BabyClock/Shared/SQLiteStore.swift` 为 `import SQLite3`，已修正 |
| iOS 小组件 | **WidgetKit**（**锁屏** + 桌面） | iOS 16+ 支持系统级锁屏小组件，是 iOS "不解锁记录"主路径 |
| iOS 语音 | **App Intents**（Siri / 快捷指令），`openAppWhenRun = false` | 系统自带语音，App 不录音不联网；支持参数化（奶粉毫升） |
| iOS 可视化 | **Swift Charts**（iOS 16+）+ 活动带用 `Canvas` 手绘 | 趋势图用 Charts；24h 泳道时间带 Charts 不擅长，手绘更可控 |
| Android UI | **Jetpack Compose**（minSdk 26） | 声明式、与 SwiftUI 心智一致 |
| Android 存储 | **Room**（SQLite ORM） | 官方、离线、协程友好 |
| Android 小组件 | **Glance**（AppWidget，**仅桌面**） | ⚠️ Android 自 5.0 起无锁屏小组件，Glance 只能放桌面，**不构成"不解锁"路径** |
| Android 快捷入口 | **锁屏常驻通知 action + 前台服务** | Android 端"不解锁记录"的唯一可靠路径，见 §6 |
| ~~Android 语音~~ | ❌ **MVP 不做** | App Shortcuts 非语音触发器；Google Conversational Actions 已于 2023-06-13 关停；App Actions BII 无对应意图类型 |
| Android 可视化 | Compose **`Canvas`** 手绘活动带 + 趋势图 | 与 iOS 手绘方案对齐，避免引入 MPAndroidChart 等第三方库破坏零依赖原则 |
| 跨端共享 | **共享业务规格 + 共享验收用例**（非共享代码） | 两端各自实现同一状态机，保证行为一致 |

> 离线红线：两端均不引入任何网络库（无 URLSession/OkHttp 业务请求）。仅调用系统能力（语音助手、通知、分享面板）。构建期可加 lint 规则禁止网络权限/依赖。

> **Android App Shortcuts 的正确定位**：`shortcuts.xml` 仍保留，但它是**桌面长按图标的快捷方式**（需解锁到桌面），不是语音入口，也不是锁屏入口。v1.0 文档中"含 voice 触发"的表述已删除。
>
> **V1.2 待评估**：`androidx.appfunctions`（AppFunctions，接入 Android 智能体系统 / Gemini）可能是 Android 未来的语音/智能体入口。**尚未核实 minSdk、地区与厂商可用范围，不得进入 MVP 关键路径。**

## 2. 领域模型（两端一致的规范）

### 2.1 事件类型

```
EventType   { FEED(吃奶), SLEEP(睡觉), MEDICINE(吃药), POOP(排便) }
EventKind   { INTERVAL, INSTANT }
FeedMethod  { BREAST(母乳), FORMULA(奶粉) }        // 仅 FEED 使用
BreastSide  { LEFT, RIGHT, BOTH }                  // 仅 FEED/BREAST，可空

  FEED, SLEEP        -> INTERVAL   // 有开始/结束，会打断
  MEDICINE, POOP     -> INSTANT    // 单一时刻，不打断

  FEED/BREAST   -> INTERVAL，正常计时（start < end）
  FEED/FORMULA  -> INTERVAL，**零时长段**（start == end），一次性提交 + volume_ml
```

**为什么奶粉是零时长 INTERVAL 而不是 INSTANT**：奶粉语义上是"某时刻喝了 N ml"，但现实中喂奶粉会打断睡眠。若建模为 INSTANT，会撞上已评审确认的"瞬时事件不打断时间段"取舍，导致睡眠段不结束、数据失真。建模为零时长 INTERVAL 后打断语义天然正确，且 `submit` 主流程与 T1–T6 用例零改动。完整论证见 `shared/state-machine.md`。

### 2.2 数据表（SQLite）

```sql
CREATE TABLE baby (
  id         TEXT PRIMARY KEY,
  name       TEXT NOT NULL,
  birthday   INTEGER,            -- epoch ms, nullable
  created_at INTEGER NOT NULL
);

CREATE TABLE event (
  id          TEXT PRIMARY KEY,
  baby_id     TEXT NOT NULL,
  type        TEXT NOT NULL,     -- FEED|SLEEP|MEDICINE|POOP
  kind        TEXT NOT NULL,     -- INTERVAL|INSTANT
  feed_method TEXT,              -- BREAST|FORMULA；仅 type=FEED 非空     [v1.1 新增]
  volume_ml   INTEGER,           -- 毫升；仅 feed_method=FORMULA 必填    [v1.1 新增]
  breast_side TEXT,              -- LEFT|RIGHT|BOTH；仅 BREAST，可空     [v1.1 新增]
  start_at    INTEGER NOT NULL,  -- epoch ms; INSTANT 时即发生时刻
  end_at      INTEGER,           -- epoch ms; null=进行中(仅INTERVAL); INSTANT恒为null
                                 -- FORMULA: end_at == start_at（零时长）
  ongoing     INTEGER NOT NULL DEFAULT 0, -- 1=进行中(全局最多一条=1)；FORMULA 恒为 0
  note        TEXT,              -- 备注(药名等)
  source      TEXT NOT NULL DEFAULT 'APP', -- APP|WIDGET|VOICE(仅iOS)|NOTIFICATION(仅Android)
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL,
  FOREIGN KEY(baby_id) REFERENCES baby(id),
  -- v1.1 约束（对应 shared/state-machine.md 的 I4/I5）
  CHECK (type <> 'FEED' OR feed_method IN ('BREAST','FORMULA')),
  CHECK (feed_method IS NULL OR feed_method <> 'FORMULA'
         OR (volume_ml IS NOT NULL AND volume_ml > 0 AND ongoing = 0)),
  CHECK (feed_method IS NULL OR feed_method <> 'FORMULA' OR end_at = start_at)
);
CREATE INDEX idx_event_baby_start ON event(baby_id, start_at);
CREATE UNIQUE INDEX idx_event_ongoing ON event(baby_id, ongoing) WHERE ongoing = 1;
CREATE INDEX idx_event_feed_method ON event(baby_id, type, feed_method);  -- 奶量聚合用
```

> MVP 单宝宝，`baby_id` 用固定默认值，为多宝宝（V1.1+）预留。

### 2.2.1 Schema 迁移（**v1.1 必做，高风险项**）

已有设备上可能存在 v1.0 写入的记录，迁移**不得丢数据**：

| 端 | 机制 | 要点 |
|---|------|------|
| Android | Room `version = 1 → 2` + `Migration(1,2)` | `ALTER TABLE event ADD COLUMN ...` 三列；**禁止** `fallbackToDestructiveMigration()`。迁移需有单测：写入 v1 数据 → 迁移 → 断言记录数与字段完整 |
| iOS | 手写 `PRAGMA user_version` 判断 + `ALTER TABLE` | 迁移前**先复制一份 DB 文件做备份**（同容器内 `.bak`），迁移失败时不静默降级、不删原库 |

**历史数据回填规则**：v1.0 的 `type=FEED` 记录 `feed_method` 为空。迁移时统一回填为 `BREAST`（v1.0 的 FEED 均为计时段，语义等价母乳），`volume_ml` 留空。回填后用户在时间轴可手动改为奶粉并补毫升数。

### 2.3 核心状态机（两端必须行为一致）

权威规格见 `shared/state-machine.md`。此处为工程实现视角摘要。

**入口一：`submit(type, now, source)`** —— 母乳 / 睡觉 / 吃药 / 排便

```
function submit(type, now, source):
    kind = kindOf(type)

    if kind == INSTANT:                     # 吃药 / 排便
        insert event(type, kind=INSTANT, start_at=now, end_at=null, ongoing=0, source)
        # 不影响进行中的时间段事件
        return

    # kind == INTERVAL (母乳 / 睡觉)
    current = findOngoing()                 # ongoing==1 的时间段事件，最多一条
    if current != null and current.type == type:
        # 再次点击同类型 = 结束当前段
        # FEED 命中此分支时 current 必为 BREAST（I5 保证 FORMULA 永不 ongoing）
        current.end_at = now; current.ongoing = 0; update(current)
        return
    if current != null:
        # 被打断：旧段结束于 now
        current.end_at = now; current.ongoing = 0; update(current)
    # 开启新的进行中段
    insert event(type, kind=INTERVAL, start_at=now, end_at=null, ongoing=1, source,
                 feed_method = (type == FEED ? BREAST : null))
```

**入口二：`submitFormula(now, volumeMl, source)`** —— 奶粉专用，一次性提交

```
function submitFormula(now, volumeMl, source):
    assert volumeMl > 0                     # 校验在调用方 UI 层完成，DB CHECK 兜底
    current = findOngoing()
    if current != null:
        current.end_at = now; current.ongoing = 0; update(current)   # 打断睡眠/母乳段
    insert event(FEED, kind=INTERVAL, feed_method=FORMULA,
                 start_at=now, end_at=now, ongoing=0,
                 volume_ml=volumeMl, source)
```

> 两个入口都必须包在**同一事务**里（"结束旧段 + 写入新记录"是原子操作），否则并发写入会破坏 I1。iOS 用 `sqlite3_exec("BEGIN IMMEDIATE")`，Android 用 `@Transaction`。

**不变量（invariants）**：
1. **I1** 任一时刻 `ongoing==1` 的记录至多一条（DB 唯一索引保证）。
2. **I2** 对任一 INTERVAL 记录：`end_at == null` ⟺ `ongoing == 1`；非空时 `end_at >= start_at`（**允许相等**，即奶粉零时长段）。
3. **I3** INSTANT 记录：`end_at == null && ongoing == 0`。
4. **I4** `start_at == end_at` 的零时长 INTERVAL **仅允许** `type==FEED && feed_method==FORMULA`（DB CHECK 约束）。
5. **I5** `feed_method==FORMULA` 的记录恒有 `ongoing==0 && volume_ml != null && volume_ml > 0`（DB CHECK 约束）。
6. 时间区间不重叠：INTERVAL 之间按 **左闭右开 `[start_at, end_at)`** 判定，因此"旧段结束于 t、新段开始于 t"不算重叠。零时长段 `[t, t)` 为空集，不与任何段重叠。编辑/补记时需重算校验。

### 2.4 统计与活动带数据装配

**跨天时长拆分**

```
function splitByDay(start, end):
    # 把 [start,end) 按本地时区自然日边界(00:00)切分，返回 [(dayKey, ms), ...]
    # 例：SLEEP 23:00(D1) → 02:00(D2) ⇒ [(D1, 1h), (D2, 2h)]
    # 零时长段（奶粉）⇒ [(dayOf(start), 0)]
```

**聚合口径（两端必须一致，对应 PRD §3.4）**

| 指标 | SQL 口径 |
|------|---------|
| 喂奶次数 | `COUNT(*) WHERE type='FEED'`（可按 `feed_method` 再分组） |
| 母乳总时长 | `SUM(end_at - start_at) WHERE feed_method='BREAST'`（跨天需先 `splitByDay`） |
| **24h 总奶量 (ml)** | `SUM(volume_ml) WHERE feed_method='FORMULA'` —— **母乳不计入**，UI 必须标注口径（PRD AC-18） |
| 睡眠总时长 / 段数 | `SUM(end_at-start_at)` / `COUNT(*)` WHERE type='SLEEP'，跨天先拆分 |

> ⚠️ 进行中段（`ongoing=1`）在统计时按 `end_at = now` 参与计算，但**不得写回数据库**。

**24h 活动带数据装配**

```
function buildDayRibbon(dayKey):
    # 返回四条泳道，每条为 [(startMin, endMin, payload)]，Min = 当日 0 点起的分钟偏移
    1. 查询 [dayStart - 24h, dayEnd + 24h) 的事件（覆盖跨天段）
    2. INTERVAL：与 [dayStart, dayEnd) 求交，裁剪到当日范围
       - 裁剪后 startMin == endMin 且非 FORMULA ⇒ 不渲染（当日无可见部分）
       - duration < 3min ⇒ 强制 endMin = startMin + MIN_VISIBLE_WIDTH（PRD §3.4.1）
    3. FORMULA：渲染为标记点 + volume_ml 气泡，不画色条
    4. INSTANT：渲染为圆点，落在 startMin
    5. ongoing 段：endMin = min(now, dayEnd)，标记"未结束"端点样式
```

复杂度：单日 O(n)，n 为事件数。渲染层用 Canvas 手绘，避免为泳道图引入图表库。

## 3. 目录结构

```
D:/babyClock/
├── docs/         PRD.md (v1.1), ARCHITECTURE.md (v1.1)
├── design/       design-tokens.json, mockup.html   ← 待更新：5按钮首页/毫升面板/24h活动带/通知样式
├── shared/       state-machine.md（两端共用的行为规格与测试用例，**权威来源**）
├── ios/          源码以文件形式提供，需在 Xcode 组装（无 .xcodeproj 二进制）
│   ├── BabyClock/            主 App（SwiftUI + 系统 SQLite3）
│   │   └── Shared/           App Group 共享的 SQLiteStore + EventStateMachine
│   ├── BabyClockWidget/      WidgetKit 锁屏/桌面小组件
│   ├── BabyClockIntents/     App Intents（Siri 语音，含奶粉毫升参数）
│   └── BabyClockTests/       EventStateMachineTests.swift
└── android/      Gradle 工程（Compose + Room + Glance + Shortcuts + 通知）
    └── app/src/main/java/com/babyclock/
        ├── data/             Room: AppDatabase, EventDao, EventEntity
        ├── domain/           EventStateMachine（与 shared/ 规格逐条对齐）
        ├── ui/               Compose 首页/时间轴/活动带
        ├── widget/           Glance 桌面小组件
        ├── notification/     [v1.1 新增] 常驻通知 + 前台服务 + action 处理
        └── EventStateMachineTest.kt
```

> iOS 存储实现为 `ios/BabyClock/Shared/SQLiteStore.swift`，`import SQLite3`（系统 C API），**无 GRDB、无任何第三方依赖**（无 Package.swift / Podfile）。

## 4. 离线与隐私实现要点

- **iOS**：DB 存于 App Group 容器（`group.com.babyclock`），主 App 与 Widget / App Intent 共享同一 SQLite 文件；写入后调用 `WidgetCenter.reloadAllTimelines()`。文件保护等级要求见 §7。
- **Android**：Room DB 存于应用私有目录；Glance 小组件、App Shortcuts、**通知 action（§6）** 全部通过同一 `EventRepository`（进程内单例）写入，写后触发小组件与通知内容刷新。**三个入口必须共用同一 Repository，不得各自持有 DB 句柄**，否则 ongoing 唯一性无法保证。
- **不申请网络权限**：Android `AndroidManifest.xml` 不含 `INTERNET`；iOS 无 ATS 业务请求。构建期依赖扫描确认无网络库。
- 通知与前台服务均为**纯本地组件**，不涉及任何网络推送（无 FCM/APNs）。

## 5. 双端能力矩阵（**不对称，勿写统一规格**）

| 能力 | iOS | Android |
|------|-----|---------|
| 锁屏小组件 | ✅ WidgetKit（iOS 16+） | ❌ 系统自 5.0 起移除 |
| 桌面小组件 | ✅ WidgetKit | ✅ Glance |
| 自定义语音短语 | ✅ App Intents / Siri，支持参数（毫升） | ❌ Conversational Actions 已关停（2023-06-13）；App Shortcuts 非语音 |
| **锁屏不解锁点击记录** | ✅ 锁屏小组件 + Siri | ✅ **常驻通知 action**（§6） |
| 长按图标快捷方式 | ✅ Siri Shortcuts | ✅ App Shortcuts（`shortcuts.xml`） |
| 实时活动 / 灵动岛 | ✅ Live Activities（V1.2 可评估） | ❌ 无对等能力 |
| 智能体接入 | — | 🟡 `androidx.appfunctions`（V1.2 待评估，未核实可用范围） |

## 6. Android 锁屏常驻通知与前台服务（v1.1 新增，P0）

对应 PRD §3.9。这是 Android 端"不解锁一键记录"的**唯一可靠路径**。

### 6.1 组件构成

```
RecordForegroundService (foregroundService, type=specialUse)
  └─ 持有并持续更新 RecordNotification
       ├─ 标题：进行中事件 + 已持续时长（无则"宝宝记录"）
       ├─ 副标题：距上次喂奶相对时间
       └─ actions（PendingIntent → RecordActionReceiver）
            母乳 / 奶粉 / 睡觉 / 吃药 / 排便
            ↑ 进行中类型的文案动态变为"结束 XX"

RecordActionReceiver (BroadcastReceiver)
  └─ EventRepository.submit(...) / submitFormula(...)   // source = NOTIFICATION
       └─ 刷新通知 + Glance
```

### 6.2 关键实现约束

| 约束 | 说明 |
|------|------|
| `setAuthenticationRequired(false)` | **必须为 false**。设 true 会让锁屏点击强制解锁，功能直接失效（PRD AC-19） |
| `setOngoing(true)` + 前台服务 | Android 14+ 用户可划掉普通 ongoing 通知，必须挂前台服务才稳定常驻 |
| `foregroundServiceType="specialUse"` | API 34+ 必须声明类型；Play 上架需提交用途说明 |
| 静音 | `IMPORTANCE_LOW`、无声、无震动、无 lights。**它是记录入口，不是提醒**——PRD §3.4 明确不做任何主动提醒，通知文案不得出现"该喂奶了"类表述 |
| 计时刷新 | 进行中段的"已持续时长"**不要每秒刷新通知**（耗电 + 系统限流）。用 `Chronometer`/`setWhen()` 交给系统走秒，或 1 分钟粒度更新 |
| 奶粉毫升 | action 无法弹面板。默认沿用**上次 volume_ml** 直接写入 + 5 秒撤销窗口；无历史档位时降级唤起 App 面板 |
| 撤销 | `formula_undone` 埋点；撤销仅回滚最近一条 |
| 权限拒绝 | `POST_NOTIFICATIONS`（API 33+）被拒 → 不启动前台服务，降级为桌面小组件 + App 内记录，设置页保留重开入口（PRD AC-20） |
| ROM 保活 | MIUI/EMUI/ColorOS 激进杀后台。设置页提供分厂商图文引导；App 启动时检测通知是否存活并重建 |

## 7. iOS 锁屏写入与文件保护（v1.1 新增，**静默丢数据风险**）

锁屏状态下 Widget / App Intent 在后台写 App Group 容器里的 SQLite，受 iOS Data Protection 约束：

| 保护等级 | 锁屏可写？ | 结论 |
|---------|-----------|------|
| `NSFileProtectionComplete` | ❌ 锁屏后文件不可访问 | **禁止**，会导致记录静默丢失 |
| `NSFileProtectionCompleteUntilFirstUserAuthentication` | ✅ 开机后首次解锁起即可访问 | **采用此等级** |
| `NSFileProtectionNone` | ✅ | 不采用（婴儿健康数据，保护过弱） |

**实施要点**：
1. 对 App Group 容器内的 DB 主文件、`-wal`、`-journal`、`.bak` **全部**显式设置 `completeUntilFirstUserAuthentication`，不依赖系统默认值。
2. SQLite 打开时若文件不可写会返回错误码——**必须检查 `sqlite3_open_v2` 返回值并把失败上报到 UI/待写缓存**，不得静默吞掉（PRD §3.1 写入失败处理）。
3. WAL 模式下 `-wal` 文件的保护等级需单独设置，容易漏。
4. **必须真机锁屏实测**（PRD AC-21），模拟器不覆盖 Data Protection 行为。

## 8. 测试策略

| 层 | 覆盖 | 说明 |
|---|------|------|
| 状态机单测 | `shared/state-machine.md` 的 **T1–T11** | 两端各一套，**断言逐条一致**。T1–T6 为 v1.0 既有用例（不变），T7–T11 为 v1.1 奶粉新增 |
| 不变量单测 | I1–I5 | 随机操作序列 fuzz，断言不变量恒成立 |
| Schema 迁移测试 | Android `MigrationTestHelper`；iOS 迁移前后对比 | 写入 v1 数据 → 迁移 → 断言记录数不变、`feed_method` 正确回填为 BREAST |
| DB 约束测试 | CHECK 约束 | 尝试写入 volume_ml=null 的 FORMULA、非 FORMULA 的零时长段，断言被拒 |
| 统计口径测试 | AC-8 / AC-12 / AC-18 | 跨天拆分、奶量只含 FORMULA、口径标注 |
| 活动带装配测试 | `buildDayRibbon` | 跨天段裁剪、< 3min 最小宽度、ongoing 端点、空数据 |
| **真机实测（不可自动化）** | AC-19 / AC-21 | Android 锁屏点通知 action；iOS 锁屏经 Widget/Siri 写入。**必须锁屏真机验证，模拟器无效** |
| ROM 兼容实测 | 通知存活 | 小米 / 华为 / OPPO / vivo 各一台，杀后台后重启 App 检测重建 |
| 离线审计 | AC-11 | 飞行模式完成全部核心操作；构建期依赖扫描确认无网络库 |
| 文案合规审查 | PRD §4 合规行 | 全量文案扫描禁词（异常/偏低/不足/达标/疑似/建议就医） |
