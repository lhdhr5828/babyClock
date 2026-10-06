import SQLite3
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
        let seq: [EventType] = [.sleep, .feed, .sleep, .feed]
        for (i, t) in seq.enumerated() {
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
    // 步骤与 Android EventStateMachineTest.formulaInvariants 逐步一致（双端同一用例序列）。
    func testFormulaInvariants() throws {
        let (m, store) = makeMachine()
        let t3 = Date(timeIntervalSince1970: 1_000_700)
        let t4 = Date(timeIntervalSince1970: 1_000_800)
        try m.submit(type: .sleep, now: t0)
        try m.submitFormula(now: t1, volumeMl: 90)
        try m.submit(type: .feed, now: t2)        // 母乳进行中
        try m.submitFormula(now: t3, volumeMl: 60) // 奶粉打断母乳
        try m.submit(type: .poop, now: t4)
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

    // MARK: - 时间轴编辑 / 删除（PRD §3.3，AC-6 / AC-7）

    // AC-7：结束早于开始 → invalidInterval，且非法编辑不得落库
    func testUpdateRejectsEndBeforeStart() throws {
        let (m, store) = makeMachine()
        var e = try m.submit(type: .sleep, now: t1)
        e.endAt = t0
        XCTAssertThrowsError(try m.update(e)) { err in
            XCTAssertEqual(err as? MachineError, .invalidInterval)
        }
        let stored = try store.allEvents(babyId: EventStateMachine.defaultBabyId).first!
        XCTAssertNil(stored.endAt)
        XCTAssertTrue(stored.ongoing)
    }

    // I4：编辑奶粉时 endAt 强制跟随 startAt；毫升非法则整笔拒绝
    func testUpdateKeepsFormulaZeroDuration() throws {
        let (m, store) = makeMachine()
        var f = try m.submitFormula(now: t0, volumeMl: 60)
        f.startAt = t2
        f.endAt = t2.addingTimeInterval(60)
        f.volumeMl = 0
        XCTAssertThrowsError(try m.update(f))          // 毫升非法 → 不落库
        f.volumeMl = 45
        try m.update(f)
        let stored = try store.allEvents(babyId: EventStateMachine.defaultBabyId).first!
        XCTAssertEqual(stored.startAt, t2)
        XCTAssertEqual(stored.endAt, t2)               // 零时长不变量被守住
        XCTAssertEqual(stored.volumeMl, 45)
    }

    // §3.1 规则 5 的坑：UI 手上那份段结束前的旧快照若被直接写回，会把已结束的段
    // 复活成"进行中"并破坏 I1 —— 所以 setBreastSide 按 id 重读当前行再改字段。
    func testSetBreastSideDoesNotResurrectEndedSegment() throws {
        let (m, store) = makeMachine()
        let stale = try m.submit(type: .feed, now: t0)  // 这份快照的 endAt 仍是 nil
        try m.submit(type: .feed, now: t1)              // 结束该段
        try m.setBreastSide(.left, id: stale.id)
        let seg = try store.allEvents(babyId: EventStateMachine.defaultBabyId)
            .first { $0.id == stale.id }!
        XCTAssertEqual(seg.breastSide, .left)
        XCTAssertFalse(seg.ongoing)
        XCTAssertNil(m.ongoing())
    }

    func testDeleteRemovesRecord() throws {
        let (m, store) = makeMachine()
        let e = try m.submit(type: .poop, now: t0)
        try m.delete(e)
        XCTAssertTrue(try store.allEvents(babyId: EventStateMachine.defaultBabyId).isEmpty)
    }

    // T12（state-machine.md）：排便类别的补填与母乳侧别同一条实现纪律 —— 按 id 重读当前行、
    // 只改这一个字段；跳过保持 nil。
    func testSetDiaperKindOnlyTouchesThatField() throws {
        let (m, store) = makeMachine()
        let e = try m.submit(type: .poop, now: t0)
        try m.submit(type: .sleep, now: t1)                 // 睡眠段进行中，排便不该牵连它
        try m.setDiaperKind(.pee, id: e.id)
        let stored = try store.allEvents(babyId: EventStateMachine.defaultBabyId).first { $0.id == e.id }!
        XCTAssertEqual(stored.diaperKind, .pee)
        XCTAssertEqual(stored.label, "小便")
        XCTAssertFalse(stored.ongoing)
        XCTAssertNotNil(m.ongoing(), "睡眠段仍在进行中")

        try m.setDiaperKind(nil, id: e.id)                  // 跳过 = 回到未区分
        let cleared = try store.allEvents(babyId: EventStateMachine.defaultBabyId).first { $0.id == e.id }!
        XCTAssertNil(cleared.diaperKind)
        XCTAssertEqual(cleared.label, "排便", "未区分时标题不猜")
    }

    func testBreastSideShowsInLabelOnlyAfterFilled() throws {
        let (m, _) = makeMachine()
        let open = try m.submit(type: .feed, now: t0)
        XCTAssertEqual(open.label, "母乳", "进行中的段还没问侧别")
        let ended = try m.submit(type: .feed, now: t1)
        try m.setBreastSide(.left, id: ended.id)
        XCTAssertEqual(try m.allEvents().first { $0.id == ended.id }?.label, "母乳 左侧")
    }
}

// MARK: - 真实 SQLite 层

/// 打在真库（临时文件）上的用例：迁移不丢数据、DELETE 真的落地、事务真的回滚。
/// 这些是 InMemoryEventStore 证明不了的 —— 内存版没有 schema，也没有第二份进程视图。
private func ev(_ id: String, _ type: EventType, _ start: Date,
                end: Date? = nil, ongoing: Bool = false,
                method: FeedMethod? = nil, ml: Int? = nil, side: BreastSide? = nil) -> BabyEvent {
    BabyEvent(id: id, babyId: EventStateMachine.defaultBabyId, type: type,
              startAt: start, endAt: end, ongoing: ongoing, note: nil,
              source: .app, createdAt: start, updatedAt: start,
              feedMethod: method, volumeMl: ml, breastSide: side)
}

final class SQLiteStoreTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private let t1 = Date(timeIntervalSince1970: 1_000_300)
    private let t2 = Date(timeIntervalSince1970: 1_000_600)
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("babyclock-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func path() -> String { dir.appendingPathComponent("main.sqlite").path }

    /// 绕过 SQLiteStore 直接用 C API 建库/塞数据，用来伪造 v1.0 时代的旧 schema。
    @discardableResult
    private func raw(_ path: String, _ sqls: [String]) throws -> [String] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            sqlite3_close(db)
            throw SQLiteStore.StoreError.openFailed(-1)
        }
        defer { sqlite3_close(db) }
        var failures: [String] = []
        for sql in sqls {
            var err: UnsafeMutablePointer<CChar>?
            if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
                failures.append("\(sql) -> \(err.map { String(cString: $0) } ?? "?")")
            }
            if let err { sqlite3_free(err) }
        }
        return failures
    }

    private func rawUserVersion(_ path: String) throws -> Int {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            sqlite3_close(db)
            throw SQLiteStore.StoreError.openFailed(-1)
        }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_ROW else { return -1 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    /// v1 → v3：三列补齐、历史 FEED 回填母乳、进行中段原样保留、改数据前留 .bak。
    func testV1MigrationKeepsRowsAndBackfillsBreast() throws {
        let p = path()
        try raw(p, [
            """
            CREATE TABLE event (id TEXT PRIMARY KEY, baby_id TEXT NOT NULL, type TEXT NOT NULL,
              start_at REAL NOT NULL, end_at REAL, ongoing INTEGER NOT NULL DEFAULT 0, note TEXT,
              source TEXT NOT NULL DEFAULT 'APP', created_at REAL NOT NULL, updated_at REAL NOT NULL);
            """,
            "INSERT INTO event VALUES('a','default','FEED',1000,1100,0,NULL,'APP',1000,1100);",
            "INSERT INTO event VALUES('b','default','SLEEP',2000,NULL,1,NULL,'APP',2000,2000);",
            "INSERT INTO event VALUES('c','default','POOP',3000,NULL,0,NULL,'APP',3000,3000);",
        ])
        XCTAssertEqual(try rawUserVersion(p), 0, "v1 库不该有版本号")

        let all = try SQLiteStore(path: p).allEvents(babyId: EventStateMachine.defaultBabyId)
        XCTAssertEqual(all.count, 3, "老记录一条都不能丢")
        XCTAssertEqual(all.first { $0.id == "a" }?.feedMethod, .breast)
        XCTAssertEqual(all.first { $0.id == "b" }?.ongoing, true)
        XCTAssertEqual(all.first { $0.id == "c" }?.type, .poop)
        XCTAssertTrue(FileManager.default.fileExists(atPath: p + ".bak"), "动数据前必须先备份")
        XCTAssertEqual(try rawUserVersion(p), 3)

        let again = try SQLiteStore(path: p).allEvents(babyId: EventStateMachine.defaultBabyId)
        XCTAssertEqual(again.count, 3, "二次打开不该重复迁移")
    }

    /// v2 → v3（用户手机上的真实路径）：只补 diaper_kind 一列，已有记录一条不丢，
    /// 旧的排便行类别为空 —— 显示回"排便"，不猜成小便或大便。
    func testV2MigrationAddsDiaperKindKeepingRows() throws {
        let p = path()
        try raw(p, [
            """
            CREATE TABLE event (id TEXT PRIMARY KEY, baby_id TEXT NOT NULL, type TEXT NOT NULL,
              start_at REAL NOT NULL, end_at REAL, ongoing INTEGER NOT NULL DEFAULT 0, note TEXT,
              source TEXT NOT NULL DEFAULT 'APP', created_at REAL NOT NULL, updated_at REAL NOT NULL,
              feed_method TEXT, volume_ml INTEGER, breast_side TEXT);
            """,
            "PRAGMA user_version = 2;",
            "INSERT INTO event VALUES('a','default','FEED',1000,1100,0,NULL,'APP',1000,1100,'BREAST',NULL,'LEFT');",
            "INSERT INTO event VALUES('c','default','POOP',3000,NULL,0,NULL,'APP',3000,3000,NULL,NULL,NULL);",
        ])
        XCTAssertEqual(try rawUserVersion(p), 2)

        let store = try SQLiteStore(path: p)
        let all = try store.allEvents(babyId: EventStateMachine.defaultBabyId)
        XCTAssertEqual(all.count, 2, "两行都要在")
        XCTAssertEqual(all.first { $0.id == "a" }?.breastSide, .left, "v2 已有的列不能被动过")
        XCTAssertNil(all.first { $0.id == "c" }?.diaperKind, "迁移不猜类别")
        XCTAssertEqual(try rawUserVersion(p), 3)

        // 迁移后写入路径要能真的把 diaper_kind 存进去、读回来
        let m = EventStateMachine(store: store)
        let poop = try m.submit(type: .poop, now: t0)
        try m.setDiaperKind(.pee, id: poop.id)
        let reread = try SQLiteStore(path: p)   // 换个句柄，确认落的是磁盘不是内存
            .allEvents(babyId: EventStateMachine.defaultBabyId)
            .first { $0.id == poop.id }
        XCTAssertEqual(reread?.diaperKind, .pee)
        XCTAssertEqual(reread?.label, "小便")
    }

    /// v1 老库里已有两条 ongoing（当年多进程竞态留下的脏数据）时，唯一索引建不上，
    /// 但库必须照常可读 —— 不能把用户唯一的记录锁在门外。
    func testMigrationToleratesLegacyDuplicateOngoing() throws {
        let p = path()
        try raw(p, [
            "CREATE TABLE event (id TEXT PRIMARY KEY, baby_id TEXT NOT NULL, type TEXT NOT NULL,"
            + " start_at REAL NOT NULL, end_at REAL, ongoing INTEGER NOT NULL DEFAULT 0, note TEXT,"
            + " source TEXT NOT NULL DEFAULT 'APP', created_at REAL NOT NULL, updated_at REAL NOT NULL);",
            "INSERT INTO event VALUES('a','default','SLEEP',1000,NULL,1,NULL,'APP',1000,1000);",
            "INSERT INTO event VALUES('b','default','FEED',1100,NULL,1,NULL,'APP',1100,1100);",
        ])
        let all = try SQLiteStore(path: p).allEvents(babyId: EventStateMachine.defaultBabyId)
        XCTAssertEqual(all.count, 2, "脏数据可读优先于库级兜底")
    }

    /// 曾经的 delete 是空实现：删掉的记录必须在重开库后依然不存在。
    func testDeleteActuallyRemovesRowOnDisk() throws {
        let p = path()
        let machine = EventStateMachine(store: try SQLiteStore(path: p))
        let e = try machine.submit(type: .poop, now: t0)
        try machine.delete(e)
        let reopened = try SQLiteStore(path: p).allEvents(babyId: EventStateMachine.defaultBabyId)
        XCTAssertTrue(reopened.isEmpty, "删除后重开库不得复活")
    }

    /// 列绑定/读取索引写错的回归网：v1.1 三个新字段要能原样穿库回来。
    func testFormulaAndBreastSideRoundTripThroughSQLite() throws {
        let p = path()
        let machine = EventStateMachine(store: try SQLiteStore(path: p))
        try machine.submitFormula(now: t0, volumeMl: 90)
        let breast = try machine.submit(type: .feed, now: t1)
        try machine.submit(type: .feed, now: t2)
        try machine.setBreastSide(.left, id: breast.id)

        let all = try SQLiteStore(path: p).allEvents(babyId: EventStateMachine.defaultBabyId)
        let f = try XCTUnwrap(all.first { $0.isFormula })
        XCTAssertEqual(f.volumeMl, 90)
        XCTAssertEqual(f.endAt, f.startAt)
        XCTAssertFalse(f.ongoing)
        let b = try XCTUnwrap(all.first { $0.feedMethod == .breast })
        XCTAssertEqual(b.breastSide, .left)
        XCTAssertEqual(b.endAt, t2)
        XCTAssertFalse(b.ongoing)
    }

    /// ARCH §2.3：「结束旧段 + 写入新段」中途失败必须整体回滚，不留半条记录。
    func testTransactionRollbackLeavesNoHalfWrittenRecord() throws {
        struct Boom: Error {}
        let p = path()
        let store = try SQLiteStore(path: p)
        XCTAssertThrowsError(try store.transaction {
            try store.insert(ev("x", .sleep, t0, ongoing: true))
            throw Boom()
        })
        let reopened = try SQLiteStore(path: p).allEvents(babyId: EventStateMachine.defaultBabyId)
        XCTAssertTrue(reopened.isEmpty, "回滚后不该留下半条记录")
    }

    /// I1 的库级兜底：部分唯一索引让第二条 ongoing 写不进去。
    func testOngoingUniqueIndexRejectsSecondOngoingRow() throws {
        let store = try SQLiteStore(path: path())
        try store.insert(ev("a", .sleep, t0, ongoing: true))
        XCTAssertThrowsError(try store.insert(ev("b", .sleep, t1, ongoing: true)))
        let ongoing = try store.allEvents(babyId: EventStateMachine.defaultBabyId).filter { $0.ongoing }
        XCTAssertEqual(ongoing.count, 1)
    }
}
