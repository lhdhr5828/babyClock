package com.babyclock.data;

import androidx.annotation.NonNull;
import androidx.room.DatabaseConfiguration;
import androidx.room.InvalidationTracker;
import androidx.room.RoomDatabase;
import androidx.room.RoomOpenHelper;
import androidx.room.migration.AutoMigrationSpec;
import androidx.room.migration.Migration;
import androidx.room.util.DBUtil;
import androidx.room.util.TableInfo;
import androidx.sqlite.db.SupportSQLiteDatabase;
import androidx.sqlite.db.SupportSQLiteOpenHelper;
import java.lang.Class;
import java.lang.Override;
import java.lang.String;
import java.lang.SuppressWarnings;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import javax.annotation.processing.Generated;

@Generated("androidx.room.RoomProcessor")
@SuppressWarnings({"unchecked", "deprecation"})
public final class AppDatabase_Impl extends AppDatabase {
  private volatile EventDao _eventDao;

  @Override
  @NonNull
  protected SupportSQLiteOpenHelper createOpenHelper(@NonNull final DatabaseConfiguration config) {
    final SupportSQLiteOpenHelper.Callback _openCallback = new RoomOpenHelper(config, new RoomOpenHelper.Delegate(2) {
      @Override
      public void createAllTables(@NonNull final SupportSQLiteDatabase db) {
        db.execSQL("CREATE TABLE IF NOT EXISTS `event` (`id` TEXT NOT NULL, `babyId` TEXT NOT NULL, `type` TEXT NOT NULL, `startAt` INTEGER NOT NULL, `endAt` INTEGER, `ongoing` INTEGER NOT NULL, `note` TEXT, `source` TEXT NOT NULL, `createdAt` INTEGER NOT NULL, `updatedAt` INTEGER NOT NULL, `feed_method` TEXT, `volume_ml` INTEGER, `breast_side` TEXT, PRIMARY KEY(`id`))");
        db.execSQL("CREATE TABLE IF NOT EXISTS room_master_table (id INTEGER PRIMARY KEY,identity_hash TEXT)");
        db.execSQL("INSERT OR REPLACE INTO room_master_table (id,identity_hash) VALUES(42, 'd44a5a63f405c79a83fe43fce9f75e72')");
      }

      @Override
      public void dropAllTables(@NonNull final SupportSQLiteDatabase db) {
        db.execSQL("DROP TABLE IF EXISTS `event`");
        final List<? extends RoomDatabase.Callback> _callbacks = mCallbacks;
        if (_callbacks != null) {
          for (RoomDatabase.Callback _callback : _callbacks) {
            _callback.onDestructiveMigration(db);
          }
        }
      }

      @Override
      public void onCreate(@NonNull final SupportSQLiteDatabase db) {
        final List<? extends RoomDatabase.Callback> _callbacks = mCallbacks;
        if (_callbacks != null) {
          for (RoomDatabase.Callback _callback : _callbacks) {
            _callback.onCreate(db);
          }
        }
      }

      @Override
      public void onOpen(@NonNull final SupportSQLiteDatabase db) {
        mDatabase = db;
        internalInitInvalidationTracker(db);
        final List<? extends RoomDatabase.Callback> _callbacks = mCallbacks;
        if (_callbacks != null) {
          for (RoomDatabase.Callback _callback : _callbacks) {
            _callback.onOpen(db);
          }
        }
      }

      @Override
      public void onPreMigrate(@NonNull final SupportSQLiteDatabase db) {
        DBUtil.dropFtsSyncTriggers(db);
      }

      @Override
      public void onPostMigrate(@NonNull final SupportSQLiteDatabase db) {
      }

      @Override
      @NonNull
      public RoomOpenHelper.ValidationResult onValidateSchema(
          @NonNull final SupportSQLiteDatabase db) {
        final HashMap<String, TableInfo.Column> _columnsEvent = new HashMap<String, TableInfo.Column>(13);
        _columnsEvent.put("id", new TableInfo.Column("id", "TEXT", true, 1, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsEvent.put("babyId", new TableInfo.Column("babyId", "TEXT", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsEvent.put("type", new TableInfo.Column("type", "TEXT", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsEvent.put("startAt", new TableInfo.Column("startAt", "INTEGER", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsEvent.put("endAt", new TableInfo.Column("endAt", "INTEGER", false, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsEvent.put("ongoing", new TableInfo.Column("ongoing", "INTEGER", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsEvent.put("note", new TableInfo.Column("note", "TEXT", false, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsEvent.put("source", new TableInfo.Column("source", "TEXT", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsEvent.put("createdAt", new TableInfo.Column("createdAt", "INTEGER", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsEvent.put("updatedAt", new TableInfo.Column("updatedAt", "INTEGER", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsEvent.put("feed_method", new TableInfo.Column("feed_method", "TEXT", false, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsEvent.put("volume_ml", new TableInfo.Column("volume_ml", "INTEGER", false, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsEvent.put("breast_side", new TableInfo.Column("breast_side", "TEXT", false, 0, null, TableInfo.CREATED_FROM_ENTITY));
        final HashSet<TableInfo.ForeignKey> _foreignKeysEvent = new HashSet<TableInfo.ForeignKey>(0);
        final HashSet<TableInfo.Index> _indicesEvent = new HashSet<TableInfo.Index>(0);
        final TableInfo _infoEvent = new TableInfo("event", _columnsEvent, _foreignKeysEvent, _indicesEvent);
        final TableInfo _existingEvent = TableInfo.read(db, "event");
        if (!_infoEvent.equals(_existingEvent)) {
          return new RoomOpenHelper.ValidationResult(false, "event(com.babyclock.data.BabyEvent).\n"
                  + " Expected:\n" + _infoEvent + "\n"
                  + " Found:\n" + _existingEvent);
        }
        return new RoomOpenHelper.ValidationResult(true, null);
      }
    }, "d44a5a63f405c79a83fe43fce9f75e72", "307f7bc9ad805c308add11acb52839ce");
    final SupportSQLiteOpenHelper.Configuration _sqliteConfig = SupportSQLiteOpenHelper.Configuration.builder(config.context).name(config.name).callback(_openCallback).build();
    final SupportSQLiteOpenHelper _helper = config.sqliteOpenHelperFactory.create(_sqliteConfig);
    return _helper;
  }

  @Override
  @NonNull
  protected InvalidationTracker createInvalidationTracker() {
    final HashMap<String, String> _shadowTablesMap = new HashMap<String, String>(0);
    final HashMap<String, Set<String>> _viewTables = new HashMap<String, Set<String>>(0);
    return new InvalidationTracker(this, _shadowTablesMap, _viewTables, "event");
  }

  @Override
  public void clearAllTables() {
    super.assertNotMainThread();
    final SupportSQLiteDatabase _db = super.getOpenHelper().getWritableDatabase();
    try {
      super.beginTransaction();
      _db.execSQL("DELETE FROM `event`");
      super.setTransactionSuccessful();
    } finally {
      super.endTransaction();
      _db.query("PRAGMA wal_checkpoint(FULL)").close();
      if (!_db.inTransaction()) {
        _db.execSQL("VACUUM");
      }
    }
  }

  @Override
  @NonNull
  protected Map<Class<?>, List<Class<?>>> getRequiredTypeConverters() {
    final HashMap<Class<?>, List<Class<?>>> _typeConvertersMap = new HashMap<Class<?>, List<Class<?>>>();
    _typeConvertersMap.put(EventDao.class, EventDao_Impl.getRequiredConverters());
    return _typeConvertersMap;
  }

  @Override
  @NonNull
  public Set<Class<? extends AutoMigrationSpec>> getRequiredAutoMigrationSpecs() {
    final HashSet<Class<? extends AutoMigrationSpec>> _autoMigrationSpecsSet = new HashSet<Class<? extends AutoMigrationSpec>>();
    return _autoMigrationSpecsSet;
  }

  @Override
  @NonNull
  public List<Migration> getAutoMigrations(
      @NonNull final Map<Class<? extends AutoMigrationSpec>, AutoMigrationSpec> autoMigrationSpecs) {
    final List<Migration> _autoMigrations = new ArrayList<Migration>();
    return _autoMigrations;
  }

  @Override
  public EventDao eventDao() {
    if (_eventDao != null) {
      return _eventDao;
    } else {
      synchronized(this) {
        if(_eventDao == null) {
          _eventDao = new EventDao_Impl(this);
        }
        return _eventDao;
      }
    }
  }
}
