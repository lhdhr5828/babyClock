import XCTest
@testable import BabyClock

/// 覆盖 shared/state-machine.md 的 T1..T6 与跨天拆分（PRD AC-1..AC-4, AC-12）。
final class EventStateMachineTests: XCTestCase {

    private func makeMachine() -> (EventStateMachine, InMemoryEventStore) {
        let store = InMemoryEventStore()
        return (EventStateMachine(store: store), store)
    }
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private let t1 = Date(timeIntervalSince1970: 1_000_300)
    private let t2 = Date(timeIntervalSince1970: 1_000_600)

    // T1 / AC-1：开始睡觉
    func testStartSleep() throws {
        let (m, store) = makeMachine()
        try m.submit(type: .sleep, now: t0)
        let all = try store.allEvents(babyId: EventStateMachine.defaultBabyId)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].type, .sleep)
        XCTAssertTrue(all[0].ongoing)
        XCTAssertEqual(all[0].startAt, t0)
        XCTAssertNil(all[0].endAt)
    }

    // T2 / AC-2：睡觉被吃奶打断
    func testSleepInterruptedByFeed() throws {
        let (m, store) = makeMachine()
        try m.submit(type: .sleep, now: t0)
        try m.submit(type: .feed, now: t1)
        let all = try store.allEvents(babyId: EventStateMachine.defaultBabyId)
        let sleep = all.first { $0.type == .sleep }!
        let feed = all.first { $0.type == .feed }!
        XCTAssertFalse(sleep.ongoing)
        XCTAssertEqual(sleep.endAt, t1)
        XCTAssertTrue(feed.ongoing)
        XCTAssertEqual(feed.startAt, t1)
    }

    // T3 / AC-3：排便（瞬时）不打断睡觉
    func testInstantDoesNotInterrupt() throws {
        let (m, store) = makeMachine()
        try m.submit(type: .sleep, now: t0)
        try m.submit(type: .poop, now: t1)
        let all = try store.allEvents(babyId: EventStateMachine.defaultBabyId)
        let sleep = all.first { $0.type == .sleep }!
        let poop = all.first { $0.type == .poop }!
        XCTAssertTrue(sleep.ongoing)
        XCTAssertNil(sleep.endAt)
        XCTAssertFalse(poop.ongoing)
        XCTAssertNil(poop.endAt)
        XCTAssertEqual(poop.startAt, t1)
    }

    // T4 / AC-4：再次点击同类型 = 结束
    func testTapSameTypeEnds() throws {
        let (m, store) = makeMachine()
        try m.submit(type: .feed, now: t0)
        try m.submit(type: .feed, now: t1)
        let all = try store.allEvents(babyId: EventStateMachine.defaultBabyId)
        XCTAssertEqual(all.count, 1)
        XCTAssertFalse(all[0].ongoing)
        XCTAssertEqual(all[0].endAt, t1)
        XCTAssertNil(m.ongoing())
    }

    // T5：睡觉 -> 吃药(瞬时) -> 吃奶(打断)
    func testMixedSequence() throws {
        let (m, store) = makeMachine()
        try m.submit(type: .sleep, now: t0)
        try m.submit(type: .medicine, now: t1)
        try m.submit(type: .feed, now: t2)
        let all = try store.allEvents(babyId: EventStateMachine.defaultBabyId)
        let sleep = all.first { $0.type == .sleep }!
        let feed = all.first { $0.type == .feed }!
        XCTAssertEqual(sleep.endAt, t2)
        XCTAssertEqual(feed.startAt, t2)
        XCTAssertTrue(feed.ongoing)
        XCTAssertEqual(all.filter { $0.type == .medicine }.count, 1)
    }

    // T6 / I1：进行中事件至多一条
    func testAtMostOneOngoing() throws {
        let (m, store) = makeMachine()
        for (i, t) in [.sleep, .feed, .sleep, .feed] as [EventType] {
            try m.submit(type: t, now: Date(timeIntervalSince1970: 1_000_000 + Double(i) * 100))
        }
        let all = try store.allEvents(babyId: EventStateMachine.defaultBabyId)
        XCTAssertEqual(all.filter { $0.ongoing }.count, 1)
    }

    // AC-12：跨天时长拆分
    func testSplitByDay() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = DateComponents(calendar: cal, year: 2026, month: 9, day: 10, hour: 23).date!
        let end = DateComponents(calendar: cal, year: 2026, month: 9, day: 11, hour: 2).date!
        let parts = EventStateMachine.splitByDay(start: start, end: end, calendar: cal)
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0].seconds, 3600, accuracy: 1)   // 23:00-24:00 = 1h
        XCTAssertEqual(parts[1].seconds, 7200, accuracy: 1)   // 00:00-02:00 = 2h
    }

    // MARK: - v1.1 奶粉（T7–T11，断言与 Android 及 state-machine.md 一致）

    // 母乳经 submit 落库须标记 feedMethod=BREAST（T5 隐含，此处显式）
    func testSubmitFeedIsBreast() throws {
        let (m, store) = makeMachine()
        try m.submit(type: .feed, now: t0)
        let all = try store.allEvents(babyId: EventStateMachine.defaultBabyId)
        XCTAssertEqual(all[0].feedMethod, .breast)
        XCTAssertFalse(all[0].isFormula)
        XCTAssertNil(all[0].volumeMl)
    }

    // T7：奶粉一次性提交 → 零时长 FEED/FORMULA 段
    func testFormulaBasic() throws {
        let (m, store) = makeMachine()
        try m.submitFormula(now: t0, volumeMl: 60)
        let all = try store.allEvents(babyId: EventStateMachine.defaultBabyId)
        XCTAssertEqual(all.count, 1)
        let f = all[0]
        XCTAssertEqual(f.type, .feed)
        XCTAssertEqual(f.feedMethod, .formula)
        XCTAssertTrue(f.isFormula)
        XCTAssertEqual(f.startAt, t0)
        XCTAssertEqual(f.endAt, t0)          // start == end
        XCTAssertFalse(f.ongoing)
        XCTAssertEqual(f.volumeMl, 60)
        XCTAssertNil(m.ongoing())
    }

    // T8：奶粉打断睡眠
    func testFormulaInterruptsSleep() throws {
        let (m, store) = makeMachine()
        try m.submit(type: .sleep, now: t0)
        try m.submitFormula(now: t1, volumeMl: 90)
        let all = try store.allEvents(babyId: EventStateMachine.defaultBabyId)
        let sleep = all.first { $0.type == .sleep }!
        let formula = all.first { $0.isFormula }!
        XCTAssertFalse(sleep.ongoing)
        XCTAssertEqual(sleep.endAt, t1)       // 睡眠结束于 now
        XCTAssertEqual(formula.startAt, t1)
        XCTAssertEqual(formula.endAt, t1)
        XCTAssertEqual(formula.volumeMl, 90)
        XCTAssertNil(m.ongoing())
    }

    // T9：奶粉连续两次 → 两条独立记录，不合并、不覆盖
    func testFormulaTwiceIndependent() throws {
        let (m, store) = makeMachine()
        try m.submitFormula(now: t0, volumeMl: 60)
        try m.submitFormula(now: t1, volumeMl: 90)
        let all = try store.allEvents(babyId: EventStateMachine.defaultBabyId)
        let formulas = all.filter { $0.isFormula }
        XCTAssertEqual(formulas.count, 2)
        XCTAssertEqual(Set(formulas.map { $0.volumeMl }), Set([60, 90]))
        XCTAssertTrue(formulas.allSatisfy { $0.startAt == $0.endAt && !$0.ongoing })
        XCTAssertNil(m.ongoing())
    }

    // T10：奶粉打断母乳
    func testFormulaInterruptsBreast() throws {
        let (m, store) = makeMachine()
        try m.submit(type: .feed, now: t0)     // 母乳进行中
        try m.submitFormula(now: t1, volumeMl: 120)
        let all = try store.allEvents(babyId: EventStateMachine.defaultBabyId)
        let breast = all.first { $0.feedMethod == .breast }!
        let formula = all.first { $0.isFormula }!
        XCTAssertFalse(breast.ongoing)
        XCTAssertEqual(breast.endAt, t1)
        XCTAssertEqual(formula.startAt, t1)
        XCTAssertEqual(formula.endAt, t1)
        XCTAssertEqual(formula.volumeMl, 120)
        XCTAssertNil(m.ongoing())
    }

    // T11 / I4·I5：零时长段必为 FEED+FORMULA；FORMULA 必 ongoing=false 且 volumeMl 非空
    func testFormulaInvariants() throws {
        let (m, store) = makeMachine()
        try m.submit(type: .sleep, now: t0)
        try m.submitFormula(now: t1, volumeMl: 60)
        try m.submit(type: .feed, now: t2)      // 母乳，打断无（此时无 ongoing）
        try m.submit(type: .poop, now: Date(timeIntervalSince1970: 1_000_700))
        let all = try store.allEvents(babyId: EventStateMachine.defaultBabyId)
        for e in all {
            if e.type.isInterval && e.startAt == e.endAt {
                // I4：零时长 INTERVAL 仅允许 FEED+FORMULA
                XCTAssertEqual(e.type, .feed)
                XCTAssertEqual(e.feedMethod, .formula)
            }
            if e.feedMethod == .formula {
                // I5：FORMULA 恒 ongoing=false 且 volumeMl 非空
                XCTAssertFalse(e.ongoing)
                XCTAssertNotNil(e.volumeMl)
            }
        }
        // I1：至多一条 ongoing
        XCTAssertLessThanOrEqual(all.filter { $0.ongoing }.count, 1)
    }

    // 规格要点 3：毫升数非正不得落库，抛 MachineError.invalidVolume
    func testFormulaRejectsNonPositiveVolume() throws {
        let (m, store) = makeMachine()
        XCTAssertThrowsError(try m.submitFormula(now: t0, volumeMl: 0)) { err in
            XCTAssertEqual(err as? MachineError, .invalidVolume)
        }
        XCTAssertThrowsError(try m.submitFormula(now: t0, volumeMl: -5))
        let all = try store.allEvents(babyId: EventStateMachine.defaultBabyId)
        XCTAssertTrue(all.isEmpty)              // 未产生半条记录
    }
}
