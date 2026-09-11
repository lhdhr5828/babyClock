# 共享行为规格（权威来源）· babyClock 事件状态机

iOS（Swift）与 Android（Kotlin）各自实现，但行为必须与本规格逐条一致。本文件是两端实现与测试的唯一权威依据。

## 事件类型与形态

| type | feed_method | kind | 说明 |
|------|-------------|------|------|
| FEED 吃奶 | `BREAST` 母乳 | INTERVAL | 时间段，开始/结束两次提交，可被打断 |
| FEED 吃奶 | `FORMULA` 奶粉 | INTERVAL | **零时长段**（`start == end`），一次性提交，携带 `volume_ml` |
| SLEEP 睡觉 | — | INTERVAL | 时间段，可被打断 |
| MEDICINE 吃药 | — | INSTANT | 瞬时，不打断时间段 |
| POOP 排便 | — | INSTANT | 瞬时，不打断时间段 |

### 为什么奶粉是 INTERVAL 而不是 INSTANT

奶粉的本质是「某时刻喝了 N 毫升」，看起来像瞬时事件。但建模为 INSTANT 会撞上 I-语义取舍——*瞬时事件不打断进行中的时间段事件*（经评审确认，见 `docs/PRD.md` §3.0）。现实中宝宝被抱起来喂奶粉时，睡眠段是**确实被打断**的；若奶粉是 INSTANT，睡眠段不会结束，数据失真。

建模为「零时长 INTERVAL」后：打断语义天然正确，`submit` 主流程与既有测试用例（T1–T6）**完全不需要改动**，奶粉走独立的 `submitFormula`。

### 事件属性

| 字段 | 适用 | 必填 | 说明 |
|------|------|------|------|
| `volume_ml` | FEED/FORMULA | 是 | 毫升数，整数。UI 提供快选档位 30/60/90/120/150 + 自定义 |
| `breast_side` | FEED/BREAST | 否 | `LEFT`/`RIGHT`/`BOTH`，可空；结束时可选一次点选，也可事后在时间轴编辑 |

## 不变量

- I1：任一时刻 `ongoing == true` 的记录至多一条。
- I2：INTERVAL 记录 `end == null` ⟺ `ongoing == true`；`end != null` 时 `end >= start`（**允许相等**）。
- I3：INSTANT 记录 `end == null && ongoing == false`。
- I4：`start == end` 的零时长 INTERVAL **仅允许** `type == FEED && feed_method == FORMULA`；其它 INTERVAL 出现零时长视为数据异常。
- I5：`feed_method == FORMULA` 的记录恒有 `ongoing == false` 且 `volume_ml != null`。

## submit(type, now, source)

用于**母乳吃奶、睡觉、吃药、排便**。奶粉不走此函数。

```
kind = kindOf(type)
if kind == INSTANT:
    insert(type, INSTANT, start=now, end=null, ongoing=false, source)
    return
# INTERVAL
current = findOngoing()
if current != null and current.type == type:
    # 再次点击=结束。FEED 命中此分支时 current 必为 BREAST（I5 保证 FORMULA 不 ongoing）
    current.end = now; current.ongoing = false; update(current)
    if type == FEED: promptBreastSideOptional(current)   # 左/右/双，可跳过
    return
if current != null:
    current.end = now; current.ongoing = false; update(current)   # 被打断
insert(type, INTERVAL, start=now, end=null, ongoing=true, source,
       feed_method = (type == FEED ? BREAST : null))
```

## submitFormula(now, volumeMl, source)

奶粉专用：一次性提交一条零时长 FEED 段。**永不产生 ongoing 记录。**

```
current = findOngoing()
if current != null:
    current.end = now; current.ongoing = false; update(current)   # 打断睡眠/母乳段
insert(FEED, INTERVAL, feed_method=FORMULA,
       start=now, end=now, ongoing=false, volume_ml=volumeMl, source)
```

要点：
1. 打断逻辑与 `submit` 的 INTERVAL 分支一致——喂奶粉时若宝宝在睡觉，睡眠段结束于 `now`。
2. 连续调用两次产生**两条独立记录**，不存在「结束当前段」语义。
3. `volumeMl` 为必填；缺失时调用方（UI/语音/通知）必须先取值，不得以 0 或 null 落库。

## 测试用例（两端断言一致）

| 用例 | 操作序列 | 期望结果 |
|------|---------|---------|
| T1 (AC-1) | submit(SLEEP, t0) | 1 条 SLEEP ongoing, start=t0, end=null |
| T2 (AC-2) | submit(SLEEP,t0); submit(FEED,t1) | SLEEP end=t1 ongoing=false；FEED start=t1 ongoing=true |
| T3 (AC-3) | submit(SLEEP,t0); submit(POOP,t1) | SLEEP 仍 ongoing end=null；新增 POOP 瞬时 start=t1 |
| T4 (AC-4) | submit(FEED,t0); submit(FEED,t1) | FEED end=t1 ongoing=false；无 ongoing |
| T5 | submit(SLEEP,t0); submit(MEDICINE,t1); submit(FEED,t2) | SLEEP end=t2；MEDICINE 瞬时 t1；FEED ongoing start=t2 feed_method=BREAST |
| T6 (I1) | 任意序列 | ongoing 记录数 <= 1 |
| T7 (奶粉基础) | submitFormula(t0, 60) | 1 条 FEED FORMULA, start=end=t0, ongoing=false, volume_ml=60 |
| T8 (奶粉打断睡眠) | submit(SLEEP,t0); submitFormula(t1, 90) | SLEEP end=t1 ongoing=false；FEED FORMULA start=end=t1 volume_ml=90；无 ongoing |
| T9 (奶粉连续两次) | submitFormula(t0,60); submitFormula(t1,90) | 2 条独立 FORMULA 记录，各自 start==end；无 ongoing |
| T10 (奶粉打断母乳) | submit(FEED,t0); submitFormula(t1,120) | BREAST 段 end=t1 ongoing=false；新增 FORMULA start=end=t1 volume_ml=120 |
| T11 (I4/I5) | 任意序列 | 零时长段必为 FEED+FORMULA；FORMULA 记录必 ongoing=false 且 volume_ml 非空 |

> **T7–T11 是 v1.1 新增**，两端单元测试必须同步补齐；T1–T6 断言不变（奶粉走独立入口，未触碰 `submit` 主流程）。

## 跨天时长拆分 splitByDay(start, end, tz)

把 `[start, end)` 按本地自然日 00:00 边界切分为 `[(dayKey, durationMs)]`，用于"某天累计时长"。
- 例：SLEEP 23:00(D1) → 02:00(D2) ⇒ [(D1, 1h), (D2, 2h)]（AC-12）。
- 零时长段（奶粉）：归属 `start` 所在自然日，`durationMs = 0`。计入当日**次数与奶量**，不计入**时长**。

## 统计聚合口径（两端一致）

| 指标 | 口径 |
|------|------|
| 喂奶次数 | FEED 记录条数（BREAST + FORMULA 合并计数，可按 feed_method 再拆分） |
| 喂奶总时长 | 仅 BREAST 段的 `end - start` 累计；FORMULA 贡献 0 |
| 24h 总奶量 (ml) | 仅 FORMULA 段 `volume_ml` 求和。**母乳不计入奶量**（无法测量），UI 必须显式标注口径，不可把「奶量」呈现为「总摄入」 |
| 睡眠总时长 | SLEEP 段按 `splitByDay` 拆分后累计 |

> ⚠️ 混合喂养时「24h 总奶量」是不完整数据。任何呈现该数字的界面都必须同时显示母乳次数/时长，避免家长误判摄入不足。

## source 取值

| 值 | 入口 | 平台 |
|----|------|------|
| `APP` | App 内按钮 | 双端 |
| `WIDGET` | 锁屏（iOS）/ 桌面（双端）小组件 | 双端 |
| `VOICE` | 系统语音（iOS Siri / App Intents） | **仅 iOS** |
| `NOTIFICATION` | 锁屏常驻通知 action 按钮 | **仅 Android** |

仅用于本地统计，不上传。
