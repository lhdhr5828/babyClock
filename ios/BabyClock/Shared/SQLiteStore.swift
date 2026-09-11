import Foundation
import SQLite3

/// 生产存储：系统自带 SQLite3（无第三方依赖、纯离线）。
/// 数据库置于 App Group 容器，主 App / Widget / App Intent 共享同一文件。
public final class SQLiteStore: EventStoring {

    public static let appGroupId = "group.com.babyclock"

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.babyclock.db")

    public enum StoreError: Error { case openFailed, prepareFailed, execFailed }

    public init(inMemory: Bool = false) throws {
        let path: String
        if inMemory {
            path = ":memory:"
        } else if let dir = FileManager.default.containerURL(
                    forSecurityApplicationGroupIdentifier: SQLiteStore.appGroupId) {
            path = dir.appendingPathComponent("babyclock.sqlite").path
        } else {
            // 回退到应用沙盒（未配置 App Group 时）
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            path = docs.appendingPathComponent("babyclock.sqlite").path
        }
        guard sqlite3_open(path, &db) == SQLITE_OK else { throw StoreError.openFailed }
        try migrate()
        applyFileProtection(path)
    }

    deinit { if let db { sqlite3_close(db) } }

    // MARK: - schema
    private func migrate() throws {
        let sql = """
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
          breast_side TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_event_baby_start ON event(baby_id, start_at);
        CREATE UNIQUE INDEX IF NOT EXISTS idx_event_ongoing ON event(baby_id, ongoing) WHERE ongoing = 1;
        """
        var err: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &err) == SQLITE_OK else {
            if let err { sqlite3_free(err) }
            throw StoreError.execFailed
        }
        try ensureColumns()
    }

    /// 非破坏式迁移：为已存在的旧库（v1，10 列）补齐 v1.1 三列。
    /// 已有行新列取 NULL → 解码为 nil，旧数据不丢（对齐 Android MIGRATION_1_2，PRD §7.2）。
    private func ensureColumns() throws {
        let existing = columnNames()
        // 列名/类型均为硬编码常量，非外部输入，无注入风险。
        let additions = [("feed_method", "TEXT"), ("volume_ml", "INTEGER"), ("breast_side", "TEXT")]
        for (name, colType) in additions where !existing.contains(name) {
            let sql = "ALTER TABLE event ADD COLUMN \(name) \(colType);"
            var err: UnsafeMutablePointer<CChar>?
            guard sqlite3_exec(db, sql, nil, nil, &err) == SQLITE_OK else {
                if let err { sqlite3_free(err) }
                throw StoreError.execFailed
            }
        }
    }

    private func columnNames() -> Set<String> {
        var cols = Set<String>()
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(event);", -1, &stmt, nil) == SQLITE_OK else { return cols }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let c = sqlite3_column_text(stmt, 1) { cols.insert(String(cString: c)) }
        }
        return cols
    }

    /// AC-21：DB 文件保护等级设为 completeUntilFirstUserAuthentication，保证「开机后曾解锁过」的
    /// 锁屏状态下仍可写入（不得为 complete，否则锁屏后写库静默失败、记录丢失）。
    /// ⚠️ 仅真机锁屏可实测（模拟器不覆盖）；对已存在的 -journal/-wal/-shm 兄弟文件一并设置。
    private func applyFileProtection(_ path: String) {
        guard path != ":memory:" else { return }
        let fm = FileManager.default
        let attrs: [FileAttributeKey: Any] = [
            .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
        ]
        for p in [path, path + "-journal", path + "-wal", path + "-shm"] where fm.fileExists(atPath: p) {
            try? fm.setAttributes(attrs, ofItemAtPath: p)
        }
    }

    // 时间以 epoch 秒(REAL)存储
    private func ts(_ d: Date) -> Double { d.timeIntervalSince1970 }
    private func date(_ v: Double) -> Date { Date(timeIntervalSince1970: v) }

    // MARK: - EventStoring
    public func findOngoing(babyId: String) -> BabyEvent? {
        var result: BabyEvent?
        queue.sync {
            let sql = "SELECT id,baby_id,type,start_at,end_at,ongoing,note,source,created_at,updated_at,feed_method,volume_ml,breast_side FROM event WHERE baby_id = ? AND ongoing = 1 LIMIT 1;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (babyId as NSString).utf8String, -1, nil)
            if sqlite3_step(stmt) == SQLITE_ROW { result = row(stmt) }
        }
        return result
    }

    public func insert(_ e: BabyEvent) throws {
        try queue.sync {
            let sql = "INSERT INTO event(id,baby_id,type,start_at,end_at,ongoing,note,source,created_at,updated_at,feed_method,volume_ml,breast_side) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?);"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw StoreError.prepareFailed }
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
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw StoreError.execFailed }
        }
    }

    public func update(_ e: BabyEvent) throws {
        try queue.sync {
            let sql = "UPDATE event SET type=?,start_at=?,end_at=?,ongoing=?,note=?,source=?,updated_at=?,feed_method=?,volume_ml=?,breast_side=? WHERE id=?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw StoreError.prepareFailed }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, e.type.rawValue); sqlite3_bind_double(stmt, 2, ts(e.startAt))
            if let end = e.endAt { sqlite3_bind_double(stmt, 3, ts(end)) } else { sqlite3_bind_null(stmt, 3) }
            sqlite3_bind_int(stmt, 4, e.ongoing ? 1 : 0)
            if let n = e.note { bindText(stmt, 5, n) } else { sqlite3_bind_null(stmt, 5) }
            bindText(stmt, 6, e.source.rawValue); sqlite3_bind_double(stmt, 7, ts(e.updatedAt))
            if let fm = e.feedMethod { bindText(stmt, 8, fm.rawValue) } else { sqlite3_bind_null(stmt, 8) }
            if let ml = e.volumeMl { sqlite3_bind_int(stmt, 9, Int32(ml)) } else { sqlite3_bind_null(stmt, 9) }
            if let bs = e.breastSide { bindText(stmt, 10, bs.rawValue) } else { sqlite3_bind_null(stmt, 10) }
            bindText(stmt, 11, e.id)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw StoreError.execFailed }
        }
    }

    public func allEvents(babyId: String) throws -> [BabyEvent] {
        try queue.sync {
            let sql = "SELECT id,baby_id,type,start_at,end_at,ongoing,note,source,created_at,updated_at,feed_method,volume_ml,breast_side FROM event WHERE baby_id = ? ORDER BY start_at ASC;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw StoreError.prepareFailed }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, babyId)
            var out: [BabyEvent] = []
            while sqlite3_step(stmt) == SQLITE_ROW { out.append(row(stmt)) }
            return out
        }
    }

    // MARK: - helpers
    private func bindText(_ stmt: OpaquePointer?, _ idx: Int32, _ s: String) {
        sqlite3_bind_text(stmt, idx, (s as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }
    private func text(_ stmt: OpaquePointer?, _ idx: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, idx) else { return nil }
        return String(cString: c)
    }
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
            breastSide: text(stmt, 12).flatMap { BreastSide(rawValue: $0) }
        )
    }
}
