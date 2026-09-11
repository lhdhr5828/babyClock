package com.babyclock

import com.babyclock.data.*
import org.junit.Assert.*
import org.junit.Test

/**
 * v1.1 数据层语义回归用例（对齐 shared/state-machine.md「统计聚合口径」与不变量 I4/I5）。
 * 这些断言锁定统计所依赖的底层数据正确性：奶量只来自 FORMULA、喂奶时长 FORMULA 贡献 0、
 * 喂奶次数合并母乳+奶粉、submit(FEED) 必为 BREAST、lastOccurrence 跨两种喂养形态。
 * 纯数据层，不触碰 UI；与既有 EventStateMachineTest（T1–T11）互补。
 */
class StatsSemanticsTest {

    private val t0 = 1_000_000L
    private val t1 = 1_060_000L   // +60s
    private val t2 = 1_120_000L   // +120s

    private fun machine(): Pair<EventStateMachine, InMemoryEventStore> {
        val s = InMemoryEventStore()
        return EventStateMachine(s) to s
    }

    private fun all(s: InMemoryEventStore) = s.allEvents(EventStateMachine.DEFAULT_BABY_ID)

    // submit(FEED) 走母乳形态：feedMethod=BREAST，且不携带 volume_ml
    @Test fun submitFeedIsBreast() {
        val (m, s) = machine()
        m.submit(EventType.FEED, t0)
        val feed = all(s).first { it.type == EventType.FEED }
        assertEquals(FeedMethod.BREAST, feed.feedMethod)
        assertNull(feed.volumeMl)
        assertTrue(feed.ongoing)
    }

    // 奶粉记录携带 volume_ml，母乳不携带 —— 保证「奶量只算 FORMULA」口径成立
    @Test fun volumeMlOnlyOnFormula() {
        val (m, s) = machine()
        m.submit(EventType.FEED, t0)            // 母乳
        m.submitFormula(t1, 90)                 // 奶粉 90ml
        m.submitFormula(t2, 60)                 // 奶粉 60ml
        val events = all(s)
        val breast = events.filter { it.feedMethod == FeedMethod.BREAST }
        val formula = events.filter { it.feedMethod == FeedMethod.FORMULA }
        assertTrue(breast.all { it.volumeMl == null })
        assertTrue(formula.all { it.volumeMl != null })
        // 24h 总奶量口径：仅 FORMULA volume_ml 求和 = 150
        assertEquals(150, formula.sumOf { it.volumeMl ?: 0 })
    }

    // 喂奶次数口径：BREAST + FORMULA 合并计数（同为 FEED 类型）
    @Test fun feedCountMergesBreastAndFormula() {
        val (m, s) = machine()
        m.submit(EventType.FEED, t0)            // 母乳 1 次
        m.submit(EventType.FEED, t1)            // 结束母乳（同段，不新增）
        m.submitFormula(t2, 90)                 // 奶粉 1 次
        val feedRecords = all(s).filter { it.type == EventType.FEED }
        // 一段母乳 + 一条奶粉 = 2 次喂奶
        assertEquals(2, feedRecords.size)
        assertEquals(1, feedRecords.count { it.feedMethod == FeedMethod.BREAST })
        assertEquals(1, feedRecords.count { it.feedMethod == FeedMethod.FORMULA })
    }

    // 喂奶总时长口径：仅 BREAST 段累计；FORMULA 为零时长，贡献 0
    @Test fun formulaContributesZeroDuration() {
        val (m, s) = machine()
        m.submit(EventType.FEED, t0)            // 母乳开始
        m.submit(EventType.FEED, t1)            // 母乳结束，时长 = t1-t0 = 60s
        m.submitFormula(t2, 120)                // 奶粉零时长
        val events = all(s)
        val breast = events.first { it.feedMethod == FeedMethod.BREAST }
        val formula = events.first { it.feedMethod == FeedMethod.FORMULA }
        assertEquals(60_000L, breast.durationMs(t1))
        assertEquals(0L, formula.durationMs(t2))    // start==end
        // 喂奶总时长 = 仅 BREAST 累计
        val feedDuration = events.filter { it.type == EventType.FEED }.sumOf { it.durationMs(t2) }
        assertEquals(60_000L, feedDuration)
    }

    // lastOccurrence(FEED) 跨母乳/奶粉取最近一次 —— 状态卡「距上次喂奶」依赖此行为
    @Test fun lastOccurrenceSpansFeedMethods() {
        val (m, s) = machine()
        m.submit(EventType.FEED, t0)            // 母乳 @ t0
        m.submit(EventType.FEED, t1)            // 结束母乳
        m.submitFormula(t2, 90)                 // 奶粉 @ t2（更晚）
        assertEquals(t2, m.lastOccurrence(EventType.FEED))
    }

    // 零时长段（奶粉）按 splitByDay 不贡献时长，但归属 start 当日（次数/奶量另算）
    @Test fun zeroDurationSplitContributesNoTime() {
        val parts = DaySplitter.splitByDay(t1, t1)   // start == end
        assertTrue(parts.isEmpty())
    }
}
