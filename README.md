# babyClock · 宝宝记录 App

新生儿**母乳 / 奶粉 / 睡觉 / 吃药 / 排便**的**纯离线**记录 App。iOS + Android 原生双端，暖色调 + iOS squircle 圆角图标。核心差异化 = **不解锁一键记录** + **24 小时活动带**让家长自己看出宝宝作息规律。

> 文档版本：**v1.2**（2026-10-06）。代码已实现 v1.1 + v1.2 增量，除**设置页与数据导出**（PRD §3.8，本轮明确不做）外均已双端落地并通过构建与单测；v1.2 是 iPhone 真机试用后的两处反馈（简述展示母乳左右侧、排便区分小/大便）。

## 交付物索引

| 阶段 | 产物 | 路径 |
|------|------|------|
| ① 功能设计 | PRD v1.2（含 **21** 条验收标准） | `docs/PRD.md` |
| ② UI 设计 | 设计 token + 高保真 HTML 原型（**v1.0 形态，待更新**） | `design/design-tokens.json`、`design/mockup.html` |
| ③ 技术方案 | 架构 v1.2（含双端能力矩阵、迁移方案、通知与文件保护） | `docs/ARCHITECTURE.md` |
| ③ 共享规格 | 两端一致的状态机权威规格 + 测试用例 T1–T12 | `shared/state-machine.md` |
| ④ iOS 代码 | Swift + SwiftUI + 系统 SQLite3 + WidgetKit + App Intents | `ios/` |
| ④ Android 代码 | Kotlin + Jetpack Compose + Room + Glance + App Shortcuts | `android/` |

## 核心逻辑（两端一致）

- **吃奶分两种形态**：母乳 = 正常时间段（开始/结束，记时长 + 左右侧，侧别同时出现在简述 chip 与时间轴）；奶粉 = **零时长段**（一次点击 + 选毫升，`start == end`）
- 睡觉 = **时间段事件**（有开始/结束，会打断）
- 吃药 / 排便 = **瞬时事件**（单一时刻，**不打断**时间段）；排便可再区分**小便 / 大便 / 大小便**（`diaper_kind`，可跳过、时间轴可补填，为空时显示"排便"）
- 提交新时间段事件（含奶粉）→ 当前进行中的时间段自动结束于"现在"
- 再次点击同一进行中类型 → 结束当前段（奶粉不适用，每次都是独立新记录）
- 任一时刻最多一个"进行中"事件；奶粉永不处于进行中

> **为什么奶粉是零时长段而不是瞬时事件**：喂奶粉时宝宝的睡眠确实被打断了。若按瞬时事件处理，会撞上"瞬时不打断时间段"这条已评审确认的取舍，导致睡眠段不结束、数据失真。零时长段让打断语义天然正确，且状态机主流程与 T1–T6 用例零改动。

详见 `shared/state-machine.md`，两端单元测试 `ios/BabyClockTests/EventStateMachineTests.swift`（27 例，含真库迁移/事务/删除）与 `android/app/src/test/java/com/babyclock/`（24 例，`EventStateMachineTest` + `StatsSemanticsTest`）断言保持一致，T1–T12 已覆盖。

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
1. 用 Android Studio (Koala+) 打开 `android/` 目录，等待 Gradle 同步；或命令行：

   ```bash
   export JAVA_HOME=/Library/Java/JavaVirtualMachines/jdk-17.jdk/Contents/Home
   ./gradlew :app:testDebugUnitTest :app:assembleDebug
   ```

   `android/local.properties` 的 `sdk.dir` 指向本机 SDK（当前为 `/opt/homebrew/share/android-commandlinetools`），换机器需改这一行。
   Gradle wrapper 钉在 **8.14.3**：AGP 8.5.2 不支持 Gradle 9.x，钉 9.x 会在同步阶段直接失败。
2. 直接 Run。`minSdk 26 / compileSdk 34`，无网络权限，Room 本地数据库（v2，含 `feed_method/volume_ml/breast_side`）。
3. 桌面长按图标可见 4 个 App Shortcuts（**桌面快捷方式，非语音入口**）；添加"宝宝记录"小组件到**桌面**（Android 无锁屏小组件）。
4. 锁屏常驻通知（PRD §3.9）已实现：前台服务 `specialUse` + `NotificationActionReceiver` 后台写库；Android 13+ 首次启动申请通知权限，被拒则降级为"小组件 + App 内记录"（AC-20）。

> 启动图标已提供自适应图标（`mipmap-anydpi-v26`）。如需更精美图标，用 Android Studio 的 Image Asset 工具替换即可。

### iOS
工程已组装完成：`ios/BabyClock.xcodeproj`（经典 pbxproj，含 `BabyClock` / `BabyClockWidget` / `BabyClockTests` 三个 target，两个 scheme：`BabyClock` 与 `BabyClockWidget`），无需再手工拖文件。

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer   # xcode-select 可能指向 CommandLineTools
xcodebuild test -project ios/BabyClock.xcodeproj -scheme BabyClock \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  CODE_SIGN_IDENTITY="-" AD_HOC_CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM=""
```

> ⚠️ 用 `CODE_SIGNING_ALLOWED=NO` 会剥掉 entitlements，App Group 容器取不到，小组件与主 App 各自读到不同路径 —— 表现是"记录成功但下次打开就没了"。
> 但**别用签名去验证 App Group**：模拟器产物的 `codesign -d --entitlements` 本来就是空 dict（CoreSimulator 走的是 `*-Simulated.xcent`，不写进最终签名），照样能读到组容器。要验证就看库有没有落在
> `~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Containers/Shared/AppGroup/<UUID>/db/babyclock.sqlite`。

> ⚠️ 本 App 无 `com.apple.developer.siri` entitlement，**任何启动路径都不得调用 `INPreferences`**（缺该 entitlement 时向它发消息抛 `NSException`，Swift 捕不住，App 启动即崩，真机模拟器都一样）。Siri 是否开启改为引导页常驻提示。

#### 标识符是参数化的

Bundle ID 与 App Group 都不再写死，走两个工程级构建设置：`BC_BUNDLE_ID_PREFIX`（默认 `com.babyclock`）与 `BC_APP_GROUP`（默认 `group.com.babyclock`）。主 App / Widget 的 entitlements、两个 Info.plist 的 `BCAppGroup`、以及 `SQLiteStore.appGroupId` 全部读同一个来源，所以只有一处真值。

这么绕一层的原因是 Apple 侧 **Bundle ID 和 App Group 全局唯一、按团队占用**：第一个免费个人团队注册过 `com.babyclock.BabyClock` 之后，第二个团队再注册同名标识会直接报 `not available`，而免费团队没有开发者后台可以释放它。用第二个团队签真机时只需命令行覆盖，仓库里的默认值一个字都不用改：

```bash
xcodebuild -project ios/BabyClock.xcodeproj -scheme BabyClock \
  -destination 'platform=iOS,id=<设备 UDID>' -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=<Team ID> \
  BC_BUNDLE_ID_PREFIX=com.babyclock.dev BC_APP_GROUP=group.com.babyclock.dev
```

> ⚠️ **换团队签名后真机会拒绝启动**（`FBSOpenApplicationErrorDomain error 3`，文案同时提"签名无效 / entitlements 不足 / 未被显式信任"三条，实际只有第三条是真的）。按这个顺序做：卸载旧包 → 装新包 → **在桌面点一次图标**让被拒记录落地 → 设置 → 通用 → VPN 与设备管理 → 信任该 Apple ID → 冷启动。
> 排查时可用的两条捷径：签名/描述文件在 Mac 侧就能验自洽（`codesign --verify --deep --strict`、`security cms -D -i embedded.mobileprovision` 比对 UDID 与 `application-groups`）；再打一个**不带 App Group 的对照包**，若同样被拒即可排除 entitlements 因素。真机锁屏写库（AC-21）仍需实测，模拟器不模拟锁屏文件保护。

## 离线与隐私

两端均不引入任何网络库、不申请网络权限（Android Manifest 无 `INTERNET`）。所有记录仅存于本机数据库。语音记录调用系统自带语音助手能力，App 自身不录音、不做云端识别。

## 落地状态

### v1.1 增量（对照 `docs/PRD.md` §7.2）

| # | 条目 | 状态 |
|---|------|------|
| 1 | 数据模型迁移（三列 + 历史 FEED 回填 BREAST，Room v1→v2 / iOS `PRAGMA user_version`） | ✅ 双端 |
| 2 | Android 锁屏常驻通知 + 前台服务（§3.9） | ✅ |
| 3 | `submitFormula` + 首页 5 按钮 + 奶粉毫升快选 + T7–T11 单测 | ✅ 双端 |
| 4 | 24 小时活动带 + 近 7 天趋势 + 奶量口径标注（AC-17/AC-18） | ✅ 双端 |
| 5 | iOS 文件保护等级（`completeUntilFirstUserAuthentication`） | ✅ 代码已设定；真机已能启动运行，**但锁屏写库（AC-21）仍未实测** |
| 6 | iOS Siri 参数化 Intent（奶粉毫升对话） | ✅ |
| 7 | 母乳左右侧点选（§3.1 规则 5，可跳过、时间轴可补填） | ✅ 双端 |
| 8 | 时间轴点击编辑 + 删除二次确认（§3.3 规则 3/4，AC-6/AC-7） | ✅ 双端 |
| 9 | 小组件尺寸区分 + 中尺寸奶粉三档（§3.5 规则 2/5） | Android ✅ 真机实测两档尺寸；iOS ⚠️ appex 打包已修好（见上），**小组件本身未在真机添加验证** |
| — | 设置页 + 数据导出（§3.8） | ❌ **本轮明确不做**，见下方待办 |
| — | `design/` 原型更新（5 按钮首页、毫升面板、活动带、通知样式） | ❌ 仍是 v1.0 形态 |
| — | 全量文案合规审查（禁词见 PRD §4） | ✅ 已按禁词清单逐条核对 UI 文案 |

### v1.2 增量（iPhone 真机试用反馈，对照 `docs/PRD.md` §7.4）

| # | 条目 | 状态 |
|---|------|------|
| 1 | 简述区展示母乳左右侧（"喂奶"突出项 + 母乳 chip 均带侧别） | ✅ 双端，Android 侧真机实测"母乳 左侧 10 秒 · 刚刚" |
| 2 | 排便区分小便 / 大便 / 大小便（`diaper_kind`，先落库再追问、可跳过、时间轴可补填） | ✅ 双端 |
| 3 | schema v2→v3（只加列不回填，未区分显示"排便"） | ✅ Android Room 在**已有 6 条记录的真库**上跑通、字段逐条一致；iOS 真机历史记录完好 |
| 4 | 时间轴与简述的类别图标同源（💧 / 💩，大小便沿用 🧷 避免挤掉时间） | ✅ 双端 |
| 5 | T12 单测 + 两端真库迁移单测 | ✅ iOS 27 例 / Android 24 例全绿 |

### 双端有意保留的差异（评审取舍，非 bug）

- **无 CHECK 约束 / 无 `kind` 列**：两端都以"状态机单层守门"为唯一约束点，`kind` 由 `EventType` 派生而非落库，避免派生数据落库后与枚举漂移。
- **iOS 小组件可点按钮需 iOS 17**（Interactive Widgets）：iOS 16 上小组件退化为纯状态展示、轻点开 App；"不解锁记录"在 16 上由 Siri 承担。
- **Siri 短语参数用 `AppEntity` / `AppEnum` 包装**：Intents 框架不接受裸 `EventType` / `Int` 作为短语参数类型。
- **Android 日期/时间选择用系统 `DatePickerDialog` / `TimePickerDialog`**：Material3 1.6 没有现成的弹窗式选择器，用系统控件可避免为此再加依赖。
- **Android 来源枚举无 VOICE**：App Shortcuts 是桌面快捷方式而非语音通道，快捷方式写入标记为 `APP`（`VOICE` 仅 iOS 使用）。
- **Android 无锁屏小组件**：系统自 5.0 起移除，改由常驻通知承担"不解锁记录"（§3.5 / §3.9）。

### 待办

1. **AC-21 iOS 真机锁屏实测**：模拟器不模拟锁屏文件保护，必须在真机上锁屏 30 秒后用锁屏小组件写一次并确认落库。
2. 设置页 + 数据导出（PRD §3.8）：导出仅限本机（SAF / 分享面板），不得引入网络权限。
3. `design/mockup.html` 与 `design/design-tokens.json` 尚未按 v1.1 / v1.2 形态更新。

### 更后续

- 多宝宝档案（数据模型已预留 `baby_id`）
- 夜间暗色暖调主题
- iOS Live Activities / 灵动岛（V1.2 可评估）
- Android `androidx.appfunctions` 智能体接入（V1.2 待评估，**需先核实 minSdk 与可用范围**）
- 多照护者数据同步：**暂不做**，与纯离线红线冲突（见 PRD §8 风险表）

## 发布签名与本机构建

release 签名不在仓库里， clone 后需要自备两份文件（都已被 `.gitignore` 挡住，**不要提交、不要 `git add -f`**）：

| 文件 | 内容 |
|------|------|
| `android/keystore.properties` | `storeFile` / `storePassword` / `keyAlias` / `keyPassword` |
| `android/keystore/*.jks` | 签名密钥本体 |

`app/build.gradle.kts` 对这两份文件做了存在性判断：**缺失时 debug 照常构建，release 退化为未签名包**，所以没配密钥也不会 clone 完就构建失败。

> 2026-10-06 起改用新密钥（`babyclock-release-v2.jks`），此前那把已作废 —— 它曾随公开仓库入库。口令只存在于本机，请自行备份到密码管理器；**丢了这份 .jks 和口令，就无法再签出可覆盖升级的包**。

## 仓库卫生（待办）

`android/**/build/` 与 `android/.gradle/` 下的构建产物、测试报告至今仍在版本控制里（约 2000 个文件）。`.gitignore` 已经覆盖这些路径，但 gitignore 对**已跟踪**文件无效，需要单独执行一次 `git rm -r --cached` 才能真正清干净。这属于纯瘦身、不涉及安全，尚未处理。
