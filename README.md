# babyClock · 宝宝记录 App

新生儿**母乳 / 奶粉 / 睡觉 / 吃药 / 排便**的**纯离线**记录 App。iOS + Android 原生双端，暖色调 + iOS squircle 圆角图标。核心差异化 = **不解锁一键记录** + **24 小时活动带**让家长自己看出宝宝作息规律。

> 文档版本：**v1.1**（2026-09-11）。代码尚为 v1.0 基线，v1.1 增量待开发，清单见 `docs/PRD.md` §7.2。

## 交付物索引

| 阶段 | 产物 | 路径 |
|------|------|------|
| ① 功能设计 | PRD v1.1（含 **21** 条验收标准） | `docs/PRD.md` |
| ② UI 设计 | 设计 token + 高保真 HTML 原型（**v1.0 形态，待更新**） | `design/design-tokens.json`、`design/mockup.html` |
| ③ 技术方案 | 架构 v1.1（含双端能力矩阵、迁移方案、通知与文件保护） | `docs/ARCHITECTURE.md` |
| ③ 共享规格 | 两端一致的状态机权威规格 + 测试用例 T1–T11 | `shared/state-machine.md` |
| ④ iOS 代码 | Swift + SwiftUI + 系统 SQLite3 + WidgetKit + App Intents | `ios/` |
| ④ Android 代码 | Kotlin + Jetpack Compose + Room + Glance + App Shortcuts | `android/` |

## 核心逻辑（两端一致）

- **吃奶分两种形态**：母乳 = 正常时间段（开始/结束，记时长 + 左右侧）；奶粉 = **零时长段**（一次点击 + 选毫升，`start == end`）
- 睡觉 = **时间段事件**（有开始/结束，会打断）
- 吃药 / 排便 = **瞬时事件**（单一时刻，**不打断**时间段）
- 提交新时间段事件（含奶粉）→ 当前进行中的时间段自动结束于"现在"
- 再次点击同一进行中类型 → 结束当前段（奶粉不适用，每次都是独立新记录）
- 任一时刻最多一个"进行中"事件；奶粉永不处于进行中

> **为什么奶粉是零时长段而不是瞬时事件**：喂奶粉时宝宝的睡眠确实被打断了。若按瞬时事件处理，会撞上"瞬时不打断时间段"这条已评审确认的取舍，导致睡眠段不结束、数据失真。零时长段让打断语义天然正确，且状态机主流程与 T1–T6 用例零改动。

详见 `shared/state-machine.md`，两端单元测试 `ios/BabyClockTests/EventStateMachineTests.swift` 与 `android/.../EventStateMachineTest.kt` 断言必须完全一致（T1–T6 已实现，**T7–T11 待补**）。

## 不解锁记录：双端方案不对称

| | iOS | Android |
|---|-----|---------|
| 主路径 | **锁屏小组件**（WidgetKit）+ **Siri 语音**（App Intents，支持"喝了 90 毫升"参数） | **锁屏常驻通知 action**（前台服务保活） |
| 次路径 | 桌面小组件 | 桌面 Glance 小组件、长按图标 App Shortcuts |
| 语音 | ✅ | ❌ 无第三方通道（Google Conversational Actions 已于 2023-06-13 关停；App Shortcuts 非语音触发器） |
| 锁屏小组件 | ✅ | ❌ 系统自 Android 5.0 起移除 |

详见 `docs/ARCHITECTURE.md` §5 双端能力矩阵。

## 打开 / 构建

### Android
1. 用 Android Studio (Koala+) 打开 `android/` 目录，等待 Gradle 同步。
2. 直接 Run。`minSdk 26`，无网络权限，Room 本地数据库。
3. 桌面长按图标可见 4 个 App Shortcuts（**桌面快捷方式，非语音入口**）；添加"宝宝记录"小组件到**桌面**（Android 无锁屏小组件）。
4. 单元测试：`./gradlew test`。

> ⚠️ v1.1 待开发：Android 锁屏常驻通知（PRD §3.9）尚未实现，这是 Android 端"不解锁记录"的唯一可靠路径。当前 Android 必须解锁到桌面才能记录。

> 启动图标已提供自适应图标（`mipmap-anydpi-v26`）。如需更精美图标，用 Android Studio 的 Image Asset 工具替换即可。

### iOS
源码以文件形式提供，需在 Xcode 中组装工程（无法用纯文本生成 `.xcodeproj` 二进制）：
1. Xcode 新建 App 项目 `BabyClock`（SwiftUI, iOS 16+）。
2. 将 `ios/BabyClock/` 下源码拖入主 target；`Shared/` 与 `Views/`、`App/` 文件加入主 target。
3. 新建 **Widget Extension** target `BabyClockWidget`，加入 `ios/BabyClockWidget/` 与 `Shared/` 源码。
4. 新建（或共用）**App Intents**：将 `ios/BabyClockIntents/RecordBabyEventIntent.swift` 加入主 target 与 Widget target。
5. 在主 App 与 Widget 两个 target 的 **Signing & Capabilities** 中开启同一个 **App Group**：`group.com.babyclock`（与 `SQLiteStore.appGroupId` 一致），以共享 SQLite 文件。
6. 运行单元测试 target，加入 `ios/BabyClockTests/EventStateMachineTests.swift`。

> 无第三方依赖：存储用系统自带 `SQLite3` C API。无网络请求。

## 离线与隐私

两端均不引入任何网络库、不申请网络权限（Android Manifest 无 `INTERNET`）。所有记录仅存于本机数据库。语音记录调用系统自带语音助手能力，App 自身不录音、不做云端识别。

## 待办 / 后续

### v1.1 增量（按 `docs/PRD.md` §7.3 建议顺序）

1. **数据模型迁移**：`event` 表加 `feed_method` / `volume_ml` / `breast_side` + Schema 迁移（Room v1→v2、iOS `PRAGMA user_version`）。历史 FEED 记录回填为 `BREAST`。**最高风险项，先做。**
2. **Android 锁屏常驻通知 + 前台服务**（PRD §3.9 / ARCH §6）。Android 端核心差异化，当前为 0；与第 1 项解耦，可并行。
3. **`submitFormula` + 首页 5 按钮 + 奶粉毫升快选面板**，补 T7–T11 双端单测。
4. **24 小时活动带**（P0）+ 近 7 天趋势图，奶量口径标注（AC-18）。
5. iOS 文件保护等级核验 + **真机锁屏实测**（AC-21，模拟器无效）。
6. iOS Siri 参数化 Intent（奶粉毫升对话）。
7. `design/` 原型更新：5 按钮首页、毫升面板、活动带、Android 通知样式。
8. 全量文案合规审查（禁词清单见 PRD §4）。

### 更后续

- 多宝宝档案（数据模型已预留 `baby_id`）
- 编辑/补记历史记录的 UI（PRD §3.3 已定义规则，UI 待补全）
- 数据导出为本地 CSV/JSON（PRD §3.8）
- 夜间暗色暖调主题
- iOS Live Activities / 灵动岛（V1.2 可评估）
- Android `androidx.appfunctions` 智能体接入（V1.2 待评估，**需先核实 minSdk 与可用范围**）
- 多照护者数据同步：**暂不做**，与纯离线红线冲突（见 PRD §8 风险表）
