package com.babyclock.data

import android.content.Context
import androidx.room.*
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class Converters {
    @TypeConverter fun fromEventType(v: EventType): String = v.name
    @TypeConverter fun toEventType(v: String): EventType = EventType.valueOf(v)
    @TypeConverter fun fromSource(v: RecordSource): String = v.name
    @TypeConverter fun toSource(v: String): RecordSource = RecordSource.valueOf(v)
    @TypeConverter fun fromFeedMethod(v: FeedMethod?): String? = v?.name
    @TypeConverter fun toFeedMethod(v: String?): FeedMethod? = v?.let { FeedMethod.valueOf(it) }
    @TypeConverter fun fromBreastSide(v: BreastSide?): String? = v?.name
    @TypeConverter fun toBreastSide(v: String?): BreastSide? = v?.let { BreastSide.valueOf(it) }
    @TypeConverter fun fromDiaperKind(v: DiaperKind?): String? = v?.name
    @TypeConverter fun toDiaperKind(v: String?): DiaperKind? = v?.let { DiaperKind.valueOf(it) }
}

@Dao
interface EventDao {
    @Query("SELECT * FROM event WHERE babyId = :babyId AND ongoing = 1 LIMIT 1")
    fun findOngoing(babyId: String): BabyEvent?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    fun insert(event: BabyEvent)

    @Update
    fun update(event: BabyEvent)

    @Query("SELECT * FROM event WHERE babyId = :babyId ORDER BY startAt ASC")
    fun allEvents(babyId: String): List<BabyEvent>

    @Delete
    fun delete(event: BabyEvent)
}

@Database(entities = [BabyEvent::class], version = 3, exportSchema = false)
@TypeConverters(Converters::class)
abstract class AppDatabase : RoomDatabase() {
    abstract fun eventDao(): EventDao

    companion object {
        @Volatile private var INSTANCE: AppDatabase? = null

        /** v1→v2：新增 feed_method / volume_ml / breast_side 三列（PRD §7.2，已有数据不可丢）。 */
        val MIGRATION_1_2 = object : Migration(1, 2) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE event ADD COLUMN feed_method TEXT")
                db.execSQL("ALTER TABLE event ADD COLUMN volume_ml INTEGER")
                db.execSQL("ALTER TABLE event ADD COLUMN breast_side TEXT")
                // 历史 FEED 段一律回填为 BREAST：v1 只有"记时长"这一种吃奶形态。
                // 不回填则该行的标题会退回类型名"吃奶"，与 iOS 迁移结果不一致。
                db.execSQL(
                    "UPDATE event SET feed_method = 'BREAST' " +
                        "WHERE type = 'FEED' AND feed_method IS NULL"
                )
            }
        }

        /**
         * v2→v3：新增 diaper_kind（排便区分小便/大便）。
         * 只加列、不回填：猜出来的大小便比空着更糟，null 在 UI 上显示为"排便"。
         */
        val MIGRATION_2_3 = object : Migration(2, 3) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE event ADD COLUMN diaper_kind TEXT")
            }
        }

        fun get(context: Context): AppDatabase =
            INSTANCE ?: synchronized(this) {
                INSTANCE ?: Room.databaseBuilder(
                    context.applicationContext,
                    AppDatabase::class.java,
                    "babyclock.db"
                ).addMigrations(MIGRATION_1_2, MIGRATION_2_3).build().also { INSTANCE = it }
            }
    }
}

/**
 * Room 支撑的 EventStore，供状态机使用（进程内单例）。
 * 事务用 [RoomDatabase.runInTransaction]：Room 2.5+ 起可重入，且内部 DAO 调用会并入同一事务。
 */
class RoomEventStore(private val db: AppDatabase) : EventStore {
    private val dao: EventDao get() = db.eventDao()

    override fun findOngoing(babyId: String) = dao.findOngoing(babyId)
    override fun insert(event: BabyEvent) = dao.insert(event)
    override fun update(event: BabyEvent) = dao.update(event)
    override fun delete(event: BabyEvent) = dao.delete(event)
    override fun allEvents(babyId: String) = dao.allEvents(babyId)
    override fun <T> transaction(body: () -> T): T =
        db.runInTransaction(java.util.concurrent.Callable { body() })
}

/**
 * 应用级仓库：单例，App / 小组件 / Shortcuts 共享同一状态机与存储，保证一致。
 * 纯离线，不发起任何网络请求。
 */
object EventRepository {
    @Volatile private var store: RoomEventStore? = null
    @Volatile private var machine: EventStateMachine? = null

    fun init(context: Context) {
        if (machine == null) synchronized(this) {
            if (machine == null) {
                val s = RoomEventStore(AppDatabase.get(context))
                store = s
                machine = EventStateMachine(s)
            }
        }
    }

    private fun m(): EventStateMachine = machine ?: error("call init(context) first")
    fun raw(): RoomEventStore = store ?: error("call init(context) first")

    suspend fun submit(type: EventType, source: RecordSource = RecordSource.APP, note: String? = null): BabyEvent =
        withContext(Dispatchers.IO) { m().submit(type, System.currentTimeMillis(), source, note) }

    suspend fun submitFormula(volumeMl: Int, source: RecordSource = RecordSource.APP, note: String? = null): BabyEvent =
        withContext(Dispatchers.IO) { m().submitFormula(System.currentTimeMillis(), volumeMl, source, note) }

    suspend fun ongoing(): BabyEvent? = withContext(Dispatchers.IO) { m().ongoing() }
    suspend fun allEvents(): List<BabyEvent> = withContext(Dispatchers.IO) { m().allEvents() }
    suspend fun lastOccurrence(type: EventType): Long? = withContext(Dispatchers.IO) { m().lastOccurrence(type) }
    suspend fun delete(event: BabyEvent): Unit = withContext(Dispatchers.IO) { m().delete(event) }
    suspend fun update(event: BabyEvent): BabyEvent = withContext(Dispatchers.IO) { m().update(event) }
    suspend fun setBreastSide(side: BreastSide?, id: String): Unit =
        withContext(Dispatchers.IO) { m().setBreastSide(side, id) }
    suspend fun setDiaperKind(kind: DiaperKind?, id: String): Unit =
        withContext(Dispatchers.IO) { m().setDiaperKind(kind, id) }
}
