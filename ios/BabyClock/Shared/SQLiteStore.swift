import Foundation
import SQLite3

/// 生产存储：系统自带 SQLite3（无第三方依赖、纯离线）。
/// 数据库置于 App Group 容器，主 App / Widget / App Intent 共享同一文件。
public final class SQLiteStore: EventStoring {

    /// App Group 容器标识：由构建设置 `BC_APP_GROUP` 经 Info.plist 的 `BCAppGroup` 注入，
    /// 与两个 target 的 entitlements 同源，所以只有一处真值。真机换签名团队时该标识
    /// 可能已被首个团队占用，命令行覆盖 `BC_APP_GROUP=` 即可，不必改仓库默认值。
    /// 读不到就返回 nil 让调用方抛 `appGroupUnavailable`：宁可显式失败，也不能退回某个
    /// 默认容器 —— 那会让主 App 与小组件各读各的库，表现为"记录成功但下次打开就没了"。
    public static let appGroupId: String? =
        (Bundle.main.infoDictionary?["BCAppGroup"] as? String).flatMap { $0.isEmpty ? nil : $0 }

    /// 表结构版本，落在 `PRAGMA user_version`（ARCH §2.2.1）。
    /// v1 = 无 feed_method / volume_ml / breast_side；v2 = 补齐三列并把历史 FEED 回填为 BREAST；
    /// v3 = 补 diaper_kind（排便区分小便/大便，历史行为 NULL = 未区分，不回填猜测值）。
    private static let schemaVersion = 3

    private var db: OpaquePointer?
    /// 迁移/初始化阶段的库文件路径，open 之后一律以 `sqlite3_db_filename` 为准
    private let initialPath: String
    private let queue = DispatchQueue(label: "com.babyclock.db")
    /// 事务嵌套深度（同一 serial queue 内自增，见 `transaction`）
    private var txDepth = 0

    public enum StoreError: Error {
        case openFailed(Int32)
        case prepareFailed
        case execFailed
        case appGroupUnavailable
    }

    /// - Parameter inMemory: 单测/预览用内存库，不落 App Group 容器。
    /// - Throws: StoreError —— 生产库打不开时**不静默回退**到别的目录，否则锁屏写入会落进
    ///   一个主 App 读不到的文件（AC-21 的静默丢数据路径）。
    public convenience init(inMemory: Bool = false) throws {
        try self.init(path: inMemory ? ":memory:" : SQLiteStore.databasePath())
    }

    /// 指定初始化：显式文件路径。生产传 App Group 容器内的库；单测传临时库，
    /// 以便验证真实的 v1→v2 迁移与 DELETE 行为（内存版 InMemoryEventStore 证明不了这些）。
    init(path: String) throws {
        initialPath = path
        var handle: OpaquePointer?
        let rc = sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        guard rc == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            throw StoreError.openFailed(rc)
        }
        db = handle
        // 主 App 与小组件是两个进程，并发写时等待而非立刻 SQLITE_BUSY
        sqlite3_busy_timeout(db, 5_000)
        queue.setSpecific(key: SQLiteStore.queueKey, value: true)
        try migrate()
    }

    deinit { if let db { sqlite3_close(db) } }

    // MARK: - 串行队列

    /// 用于判断"当前是否已在本 store 的串行队列上"，避免 queue.sync 自我死锁
    /// （`transaction { insert(...) }` 里再 sync 就是同队列 sync）。
    private static let queueKey = DispatchSpecificKey<Bool>()

    private func onQueue<T>(_ body: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: SQLiteStore.queueKey) == true { return try body() }
        return try queue.sync(execute: body)
    }

    // MARK: - 容器与文件保护（AC-21）

    /// 返回 DB 路径。**先**给容器子目录设保护等级，目录内新建的 `babyclock.sqlite` 及其
    /// `-wal`/`-journal`/`-shm` 兄弟文件随之继承；已在磁盘上的旧库在打开前逐补设。
    /// 「先建库、后设级」会留下整个启动周期的窗口落在系统默认等级上，锁屏写入即可能失败。
    private static func databasePath() throws -> String {
        let fm = FileManager.default
        guard let groupId = appGroupId,
              let container = fm.containerURL(forSecurityApplicationGroupIdentifier: groupId) else {
            throw StoreError.appGroupUnavailable
        }
        let dir = container.appendingPathComponent("db", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        applyProtection(at: dir.path)

        let dbURL = dir.appendingPathComponent("babyclock.sqlite")
        for p in [dbURL.path, dbURL.path + "-journal", dbURL.path + "-wal", dbURL.path + "-shm"]
        where fm.fileExists(atPath: p) {
            applyProtection(at: p)
        }
        return dbURL.path
    }

    private static func applyProtection(at path: String) {
        // completeUntilFirstUserAuthentication：开机后曾解锁过即锁屏可写。
        // 不得用 .complete —— 锁屏后文件不可访问，记录会静默丢失（PRD §4 数据安全行）。
        // .none 也不采用：婴儿健康数据，保护过弱（ARCH §7）。
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: path
        )
    }

    // MARK: - schema 与迁移

    /// 全新安装的完整 v3 建表语句。列名与 Android Room schema 一一对应。
    /// 首条建表必须成功；后续索引允许失败 —— 老库里若已存在两条 ongoing（v1.0 时代
    /// 多进程写竞态留下的脏数据），唯一索引建不起来，此时**读得到**比库里兜底更重要：
    /// 索引只是 I1 的兜底，状态机与事务才是主责。索引建不上也不该把用户唯一的记录锁在门外。
    private static let createTableSQL = """
    CREATE TABLE IF NOT EXISTS event (
      id TEXT PRIMARY KEY,
      baby_id TEXT NOT NULL,
      type TEXT NOT NULL,
      start_at REAL NOT NULL,
      end_at REAL,
      ongoing INTEGER NOT NULL DEFAULT 0,
      note TEXT,
      source TEXT NOT NULL DEFAULT 'APP',
      created_at REAL NOT NULL,
      updated_at REAL NOT NULL,
      feed_method TEXT,
      volume_ml INTEGER,
      breast_side TEXT,
      diaper_kind TEXT
    );
    """
    private static let createIndexesSQL = [
        "CREATE INDEX IF NOT EXISTS idx_event_baby_start ON event(baby_id, start_at);",
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_event_ongoing ON event(baby_id, ongoing) WHERE ongoing = 1;",
        "CREATE INDEX IF NOT EXISTS idx_event_feed_method ON event(baby_id, type, feed_method);",
    ]

    private func migrate() throws {
        guard tableExists("event") else {
            try exec(SQLiteStore.createTableSQL)
            SQLiteStore.createIndexesSQL.forEach { try? exec($0) }
            try exec("PRAGMA user_version = \(SQLiteStore.schemaVersion);")
            return
        }
        // 老库（v1/v2）：非破坏式补列，已有行新列为 NULL（对齐 Android MIGRATION_1_2 / _2_3）
        try ensureColumns()
        guard try userVersion() < SQLiteStore.schemaVersion else { return }
        try backupDatabaseFile()   // 动数据前先备份，失败不静默降级（ARCH §2.2.1）
        // 回填：v1.0 的 FEED 全部是计时段，语义等价母乳（state-machine.md 事件类型表）。
        // diaper_kind 不回填 —— 猜出来的大小便比空着更糟，UI 对 NULL 显示"排便"。
        try exec("""
        UPDATE event SET feed_method = 'BREAST'
        WHERE type = 'FEED' AND feed_method IS NULL;
        """)
        SQLiteStore.createIndexesSQL.forEach { try? exec($0) }
        try exec("PRAGMA user_version = \(SQLiteStore.schemaVersion);")
    }

    /// 迁移前在同目录复制一份 .bak（只留最近一份，避免越攒越多）。
    private func backupDatabaseFile() throws {
        guard initialPath != ":memory:" else { return }
        let fm = FileManager.default
        let bak = initialPath + ".bak"
        if fm.fileExists(atPath: bak) { try? fm.removeItem(atPath: bak) }
        try fm.copyItem(atPath: initialPath, toPath: bak)
        SQLiteStore.applyProtection(at: bak)   // ARCH §7：.bak 同等级，否则锁屏期间不可读
    }

    private func userVersion() throws -> Int {
        guard let stmt = prepare("PRAGMA user_version;") else { throw StoreError.prepareFailed }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int(stmt, 0)) : 0
    }

    /// 非破坏式迁移：为已存在的旧库补齐缺失列（v1 的 10 列 → v2 三列 → v3 的 diaper_kind）。已有行不丢。
    private func ensureColumns() throws {
        // 列名/类型均为硬编码常量，非外部输入，无注入风险。
        let additions = [("feed_method", "TEXT"), ("volume_ml", "INTEGER"),
                         ("breast_side", "TEXT"), ("diaper_kind", "TEXT")]
        let existing = columnNames()
        for (name, colType) in additions where !existing.contains(name) {
            try exec("ALTER TABLE event ADD COLUMN \(name) \(colType);")
        }
    }

    private func columnNames() -> Set<String> {
        guard let stmt = prepare("PRAGMA table_info(event);") else { return [] }
        defer { sqlite3_finalize(stmt) }
        var cols = Set<String>()
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let c = sqlite3_column_text(stmt, 1) { cols.insert(String(cString: c)) }
        }
        return cols
    }

    private func tableExists(_ name: String) -> Bool {
        guard let stmt = prepare(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1;"
        ) else { return false }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, name)
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    private func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &err) == SQLITE_OK else {
            if let err { sqlite3_free(err) }
            throw StoreError.execFailed
        }
    }

    // MARK: - EventStoring

    public func findOngoing(babyId: String) -> BabyEvent? {
        var result: BabyEvent?
        onQueue {
            let sql = SQLiteStore.selectColumns + " WHERE baby_id = ? AND ongoing = 1 LIMIT 1;"
            guard let stmt = prepare(sql) else { return }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, babyId)
            if sqlite3_step(stmt) == SQLITE_ROW { result = row(stmt) }
        }
        return result
    }

    public func insert(_ e: BabyEvent) throws { try onQueue { try self.insertLocked(e) } }
    public func update(_ e: BabyEvent) throws { try onQueue { try self.updateLocked(e) } }
    public func delete(_ e: BabyEvent) throws { try onQueue { try self.deleteLocked(e) } }

    public func allEvents(babyId: String) throws -> [BabyEvent] {
        try onQueue {
            let sql = SQLiteStore.selectColumns + " WHERE baby_id = ? ORDER BY start_at ASC;"
            guard let stmt = prepare(sql) else { throw StoreError.prepareFailed }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, babyId)
            var out: [BabyEvent] = []
            while sqlite3_step(stmt) == SQLITE_ROW { out.append(row(stmt)) }
            return out
        }
    }

    /// 「结束旧段 + 写入新记录」必须原子，否则中断在两条语句之间会留下两条 ongoing
    /// 或谁都不 ongoing（ARCH §2.3）。BEGIN IMMEDIATE 直接抢写锁，避免两进程各读到"无 ongoing"。
    public func transaction<T>(_ body: () throws -> T) throws -> T {
        try onQueue {
            txDepth += 1
            defer { txDepth -= 1 }
            if txDepth == 1 { try exec("BEGIN IMMEDIATE;") }
            do {
                let value = try body()
                if txDepth == 1 { try exec("COMMIT;") }
                return value
            } catch {
                if txDepth == 1 { try? exec("ROLLBACK;") }
                throw error
            }
        }
    }

    // MARK: - 语句实现（自身不加锁，由 onQueue 保证串行）

    private func insertLocked(_ e: BabyEvent) throws {
        let sql = """
        INSERT INTO event(id,baby_id,type,start_at,end_at,ongoing,note,source,created_at,updated_at,feed_method,volume_ml,breast_side,diaper_kind)
        VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?);
        """
        guard let stmt = prepare(sql) else { throw StoreError.prepareFailed }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, e.id); bindText(stmt, 2, e.babyId); bindText(stmt, 3, e.type.rawValue)
        sqlite3_bind_double(stmt, 4, ts(e.startAt))
        if let end = e.endAt { sqlite3_bind_double(stmt, 5, ts(end)) } else { sqlite3_bind_null(stmt, 5) }
        sqlite3_bind_int(stmt, 6, e.ongoing ? 1 : 0)
        if let n = e.note { bindText(stmt, 7, n) } else { sqlite3_bind_null(stmt, 7) }
        bindText(stmt, 8, e.source.rawValue)
        sqlite3_bind_double(stmt, 9, ts(e.createdAt)); sqlite3_bind_double(stmt, 10, ts(e.updatedAt))
        if let fm = e.feedMethod { bindText(stmt, 11, fm.rawValue) } else { sqlite3_bind_null(stmt, 11) }
        if let ml = e.volumeMl { sqlite3_bind_int(stmt, 12, Int32(ml)) } else { sqlite3_bind_null(stmt, 12) }
        if let bs = e.breastSide { bindText(stmt, 13, bs.rawValue) } else { sqlite3_bind_null(stmt, 13) }
        if let dk = e.diaperKind { bindText(stmt, 14, dk.rawValue) } else { sqlite3_bind_null(stmt, 14) }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw StoreError.execFailed }
    }

    private func updateLocked(_ e: BabyEvent) throws {
        let sql = """
        UPDATE event SET type=?,start_at=?,end_at=?,ongoing=?,note=?,source=?,updated_at=?,
                         feed_method=?,volume_ml=?,breast_side=?,diaper_kind=? WHERE id=?;
        """
        guard let stmt = prepare(sql) else { throw StoreError.prepareFailed }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, e.type.rawValue); sqlite3_bind_double(stmt, 2, ts(e.startAt))
        if let end = e.endAt { sqlite3_bind_double(stmt, 3, ts(end)) } else { sqlite3_bind_null(stmt, 3) }
        sqlite3_bind_int(stmt, 4, e.ongoing ? 1 : 0)
        if let n = e.note { bindText(stmt, 5, n) } else { sqlite3_bind_null(stmt, 5) }
        bindText(stmt, 6, e.source.rawValue); sqlite3_bind_double(stmt, 7, ts(e.updatedAt))
        if let fm = e.feedMethod { bindText(stmt, 8, fm.rawValue) } else { sqlite3_bind_null(stmt, 8) }
        if let ml = e.volumeMl { sqlite3_bind_int(stmt, 9, Int32(ml)) } else { sqlite3_bind_null(stmt, 9) }
        if let bs = e.breastSide { bindText(stmt, 10, bs.rawValue) } else { sqlite3_bind_null(stmt, 10) }
        if let dk = e.diaperKind { bindText(stmt, 11, dk.rawValue) } else { sqlite3_bind_null(stmt, 11) }
        bindText(stmt, 12, e.id)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw StoreError.execFailed }
    }

    private func deleteLocked(_ e: BabyEvent) throws {
        guard let stmt = prepare("DELETE FROM event WHERE id = ?;") else { throw StoreError.prepareFailed }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, e.id)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw StoreError.execFailed }
    }

    // MARK: - helpers

    private static let selectColumns = """
    SELECT id,baby_id,type,start_at,end_at,ongoing,note,source,created_at,updated_at,feed_method,volume_ml,breast_side,diaper_kind
    FROM event
    """

    private func prepare(_ sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        return stmt
    }

    /// SQLITE_TRANSIENT：让 SQLite 自行拷贝字符串。传 nil 表示不接管也不拷贝，
    /// Swift 侧的 UTF-8 缓冲区在语句执行前就可能释放 —— 那是悬垂指针。
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func bindText(_ stmt: OpaquePointer?, _ idx: Int32, _ s: String) {
        sqlite3_bind_text(stmt, idx, (s as NSString).utf8String, -1, SQLiteStore.transient)
    }

    private func text(_ stmt: OpaquePointer?, _ idx: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, idx) else { return nil }
        return String(cString: c)
    }

    // 时间以 epoch 秒(REAL)存储
    private func ts(_ d: Date) -> Double { d.timeIntervalSince1970 }
    private func date(_ v: Double) -> Date { Date(timeIntervalSince1970: v) }

    private func row(_ stmt: OpaquePointer?) -> BabyEvent {
        let typeRaw = text(stmt, 2) ?? "FEED"
        let hasEnd = sqlite3_column_type(stmt, 4) != SQLITE_NULL
        return BabyEvent(
            id: text(stmt, 0) ?? UUID().uuidString,
            babyId: text(stmt, 1) ?? EventStateMachine.defaultBabyId,
            type: EventType(rawValue: typeRaw) ?? .feed,
            startAt: date(sqlite3_column_double(stmt, 3)),
            endAt: hasEnd ? date(sqlite3_column_double(stmt, 4)) : nil,
            ongoing: sqlite3_column_int(stmt, 5) == 1,
            note: text(stmt, 6),
            source: RecordSource(rawValue: text(stmt, 7) ?? "APP") ?? .app,
            createdAt: date(sqlite3_column_double(stmt, 8)),
            updatedAt: date(sqlite3_column_double(stmt, 9)),
            feedMethod: text(stmt, 10).flatMap { FeedMethod(rawValue: $0) },
            volumeMl: sqlite3_column_type(stmt, 11) != SQLITE_NULL ? Int(sqlite3_column_int(stmt, 11)) : nil,
            breastSide: text(stmt, 12).flatMap { BreastSide(rawValue: $0) },
            diaperKind: text(stmt, 13).flatMap { DiaperKind(rawValue: $0) }
        )
    }
}
