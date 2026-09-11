package com.babyclock

import com.babyclock.data.*
import org.junit.Assert.*
import org.junit.Test
import java.util.Calendar
import java.util.TimeZone

/**
 * 覆盖 shared/state-machine.md 的 T1..T6 与跨天拆分（PRD AC-1..AC-4, AC-12）。
 * 与 iOS EventStateMachineTests 断言一致。
 */
class EventStateMachineTest {

    private val t0 = 1_000_000L
    private val t1 = 1_000_300L
    private val t2 = 1_000_600L

    private fun machine(): Pair<EventStateMachine, InMemoryEventStore> {
        val s = InMemoryEventStore()
        return EventStateMachine(s) to s
    }

    // T1 / AC-1
    @Test fun startSleep() {
        val (m, s) = machine()
        m.submit(EventType.SLEEP, t0)
        val all = s.allEvents(EventStateMachine.DEFAULT_BABY_ID)
        assertEquals(1, all.size)
        assertEquals(EventType.SLEEP, all[0].type)
        assertTrue(all[0].ongoing)
        assertEquals(t0, all[0].startAt)
        assertNull(all[0].endAt)
    }

    // T2 / AC-2
    @Test fun sleepInterruptedByFeed() {
        val (m, s) = machine()
        m.submit(EventType.SLEEP, t0)
        m.submit(EventType.FEED, t1)
        val all = s.allEvents(EventStateMachine.DEFAULT_BABY_ID)
        val sleep = all.first { it.type == EventType.SLEEP }
        val feed = all.first { it.type == EventType.FEED }
        assertFalse(sleep.ongoing)
        assertEquals(t1, sleep.endAt)
        assertTrue(feed.ongoing)
        assertEquals(t1, feed.startAt)
    }

    // T3 / AC-3：瞬时不打断
    @Test fun instantDoesNotInterrupt() {
        val (m, s) = machine()
        m.submit(EventType.SLEEP, t0)
        m.submit(EventType.POOP, t1)
        val all = s.allEvents(EventStateMachine.DEFAULT_BABY_ID)
        val sleep = all.first { it.type == EventType.SLEEP }
        val poop = all.first { it.type == EventType.POOP }
        assertTrue(sleep.ongoing)
        assertNull(sleep.endAt)
        assertFalse(poop.ongoing)
        assertNull(poop.endAt)
        assertEquals(t1, poop.startAt)
    }

    // T4 / AC-4：再次点击=结束
    @Test fun tapSameTypeEnds() {
        val (m, s) = machine()
        m.submit(EventType.FEED, t0)
        m.submit(EventType.FEED, t1)
        val all = s.allEvents(EventStateMachine.DEFAULT_BABY_ID)
        assertEquals(1, all.size)
        assertFalse(all[0].ongoing)
        assertEquals(t1, all[0].endAt)
        assertNull(m.ongoing())
    }

    // T5
    @Test fun mixedSequence() {
        val (m, s) = machine()
        m.submit(EventType.SLEEP, t0)
        m.submit(EventType.MEDICINE, t1)
        m.submit(EventType.FEED, t2)
        val all = s.allEvents(EventStateMachine.DEFAULT_BABY_ID)
        val sleep = all.first { it.type == EventType.SLEEP }
        val feed = all.first { it.type == EventType.FEED }
        assertEquals(t2, sleep.endAt)
        assertEquals(t2, feed.startAt)
        assertTrue(feed.ongoing)
        assertEquals(1, all.count { it.type == EventType.MEDICINE })
    }

    // T6 / I1
    @Test fun atMostOneOngoing() {
        val (m, s) = machine()
        listOf(EventType.SLEEP, EventType.FEED, EventType.SLEEP, EventType.FEED).forEachIndexed { i, t ->
            m.submit(t, t0 + i * 100L)
        }
        val all = s.allEvents(EventStateMachine.DEFAULT_BABY_ID)
        assertEquals(1, all.count { it.ongoing })
    }

    // AC-12：跨天拆分
    @Test fun splitByDay() {
        val cal = Calendar.getInstance(TimeZone.getTimeZone("UTC"))
        cal.set(2026, Calendar.SEPTEMBER, 10, 23, 0, 0)
        cal.set(Calendar.MILLISECOND, 0)
        val start = cal.timeInMillis
        cal.set(2026, Calendar.SEPTEMBER, 11, 2, 0, 0)
        val end = cal.timeInMillis
        val parts = DaySplitter.splitByDay(start, end, Calendar.getInstance(TimeZone.getTimeZone("UTC")))
        assertEquals(2, parts.size)
        assertEquals(3_600_000L, parts[0].second)   // 23:00-24:00 = 1h
        assertEquals(7_200_000L, parts[1].second)   // 00:00-02:00 = 2h
    }

    // T7：奶粉基础——零时长 FEED/FORMULA 段
    @Test fun formulaBasic() {
        val (m, s) = machine()
        m.submitFormula(t0, 60)
        val all = s.allEvents(EventStateMachine.DEFAULT_BABY_ID)
        assertEquals(1, all.size)
        val f = all[0]
        assertEquals(EventType.FEED, f.type)
        assertEquals(FeedMethod.FORMULA, f.feedMethod)
        assertEquals(t0, f.startAt)
        assertEquals(t0, f.endAt)
        assertFalse(f.ongoing)
        assertEquals(60, f.volumeMl)
    }

    // T8：奶粉打断睡眠
    @Test fun formulaInterruptsSleep() {
        val (m, s) = machine()
        m.submit(EventType.SLEEP, t0)
        m.submitFormula(t1, 90)
        val all = s.allEvents(EventStateMachine.DEFAULT_BABY_ID)
        val sleep = all.first { it.type == EventType.SLEEP }
        val formula = all.first { it.feedMethod == FeedMethod.FORMULA }
        assertFalse(sleep.ongoing)
        assertEquals(t1, sleep.endAt)
        assertEquals(t1, formula.startAt)
        assertEquals(t1, formula.endAt)
        assertEquals(90, formula.volumeMl)
        assertNull(m.ongoing())
    }

    // T9：奶粉连续两次产生两条独立记录
    @Test fun formulaTwiceIndependent() {
        val (m, s) = machine()
        m.submitFormula(t0, 60)
        m.submitFormula(t1, 90)
        val all = s.allEvents(EventStateMachine.DEFAULT_BABY_ID)
        val formulas = all.filter { it.feedMethod == FeedMethod.FORMULA }
        assertEquals(2, formulas.size)
        assertTrue(formulas.all { it.startAt == it.endAt })
        assertEquals(setOf(60, 90), formulas.map { it.volumeMl }.toSet())
        assertNull(m.ongoing())
    }

    // T10：奶粉打断进行中的母乳段
    @Test fun formulaInterruptsBreast() {
        val (m, s) = machine()
        m.submit(EventType.FEED, t0)   // 母乳 ongoing
        m.submitFormula(t1, 120)
        val all = s.allEvents(EventStateMachine.DEFAULT_BABY_ID)
        val breast = all.first { it.feedMethod == FeedMethod.BREAST }
        val formula = all.first { it.feedMethod == FeedMethod.FORMULA }
        assertFalse(breast.ongoing)
        assertEquals(t1, breast.endAt)
        assertEquals(t1, formula.startAt)
        assertEquals(t1, formula.endAt)
        assertEquals(120, formula.volumeMl)
    }

    // T11：不变量 I4/I5
    @Test fun formulaInvariants() {
        val (m, s) = machine()
        m.submit(EventType.SLEEP, t0)
        m.submitFormula(t1, 90)
        m.submit(EventType.FEED, t2)            // 母乳 ongoing
        m.submitFormula(t2 + 100, 60)           // 打断母乳
        m.submit(EventType.POOP, t2 + 200)
        val all = s.allEvents(EventStateMachine.DEFAULT_BABY_ID)
        // I4：零时长段(start==end)必为 FEED + FORMULA
        all.filter { it.startAt == it.endAt }.forEach {
            assertEquals(EventType.FEED, it.type)
            assertEquals(FeedMethod.FORMULA, it.feedMethod)
        }
        // I5：FORMULA 记录恒 ongoing=false 且 volume_ml 非空
        all.filter { it.feedMethod == FeedMethod.FORMULA }.forEach {
            assertFalse(it.ongoing)
            assertNotNull(it.volumeMl)
        }
        // I1：至多一条 ongoing
        assertTrue(all.count { it.ongoing } <= 1)
    }
}
