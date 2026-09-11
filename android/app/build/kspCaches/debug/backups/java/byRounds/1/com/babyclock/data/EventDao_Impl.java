package com.babyclock.data;

import android.database.Cursor;
import androidx.annotation.NonNull;
import androidx.room.EntityDeletionOrUpdateAdapter;
import androidx.room.EntityInsertionAdapter;
import androidx.room.RoomDatabase;
import androidx.room.RoomSQLiteQuery;
import androidx.room.util.CursorUtil;
import androidx.room.util.DBUtil;
import androidx.sqlite.db.SupportSQLiteStatement;
import java.lang.Class;
import java.lang.Integer;
import java.lang.Long;
import java.lang.Override;
import java.lang.String;
import java.lang.SuppressWarnings;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import javax.annotation.processing.Generated;

@Generated("androidx.room.RoomProcessor")
@SuppressWarnings({"unchecked", "deprecation"})
public final class EventDao_Impl implements EventDao {
  private final RoomDatabase __db;

  private final EntityInsertionAdapter<BabyEvent> __insertionAdapterOfBabyEvent;

  private final Converters __converters = new Converters();

  private final EntityDeletionOrUpdateAdapter<BabyEvent> __deletionAdapterOfBabyEvent;

  private final EntityDeletionOrUpdateAdapter<BabyEvent> __updateAdapterOfBabyEvent;

  public EventDao_Impl(@NonNull final RoomDatabase __db) {
    this.__db = __db;
    this.__insertionAdapterOfBabyEvent = new EntityInsertionAdapter<BabyEvent>(__db) {
      @Override
      @NonNull
      protected String createQuery() {
        return "INSERT OR REPLACE INTO `event` (`id`,`babyId`,`type`,`startAt`,`endAt`,`ongoing`,`note`,`source`,`createdAt`,`updatedAt`,`feed_method`,`volume_ml`,`breast_side`) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)";
      }

      @Override
      protected void bind(@NonNull final SupportSQLiteStatement statement,
          @NonNull final BabyEvent entity) {
        statement.bindString(1, entity.getId());
        statement.bindString(2, entity.getBabyId());
        final String _tmp = __converters.fromEventType(entity.getType());
        statement.bindString(3, _tmp);
        statement.bindLong(4, entity.getStartAt());
        if (entity.getEndAt() == null) {
          statement.bindNull(5);
        } else {
          statement.bindLong(5, entity.getEndAt());
        }
        final int _tmp_1 = entity.getOngoing() ? 1 : 0;
        statement.bindLong(6, _tmp_1);
        if (entity.getNote() == null) {
          statement.bindNull(7);
        } else {
          statement.bindString(7, entity.getNote());
        }
        final String _tmp_2 = __converters.fromSource(entity.getSource());
        statement.bindString(8, _tmp_2);
        statement.bindLong(9, entity.getCreatedAt());
        statement.bindLong(10, entity.getUpdatedAt());
        final String _tmp_3 = __converters.fromFeedMethod(entity.getFeedMethod());
        if (_tmp_3 == null) {
          statement.bindNull(11);
        } else {
          statement.bindString(11, _tmp_3);
        }
        if (entity.getVolumeMl() == null) {
          statement.bindNull(12);
        } else {
          statement.bindLong(12, entity.getVolumeMl());
        }
        final String _tmp_4 = __converters.fromBreastSide(entity.getBreastSide());
        if (_tmp_4 == null) {
          statement.bindNull(13);
        } else {
          statement.bindString(13, _tmp_4);
        }
      }
    };
    this.__deletionAdapterOfBabyEvent = new EntityDeletionOrUpdateAdapter<BabyEvent>(__db) {
      @Override
      @NonNull
      protected String createQuery() {
        return "DELETE FROM `event` WHERE `id` = ?";
      }

      @Override
      protected void bind(@NonNull final SupportSQLiteStatement statement,
          @NonNull final BabyEvent entity) {
        statement.bindString(1, entity.getId());
      }
    };
    this.__updateAdapterOfBabyEvent = new EntityDeletionOrUpdateAdapter<BabyEvent>(__db) {
      @Override
      @NonNull
      protected String createQuery() {
        return "UPDATE OR ABORT `event` SET `id` = ?,`babyId` = ?,`type` = ?,`startAt` = ?,`endAt` = ?,`ongoing` = ?,`note` = ?,`source` = ?,`createdAt` = ?,`updatedAt` = ?,`feed_method` = ?,`volume_ml` = ?,`breast_side` = ? WHERE `id` = ?";
      }

      @Override
      protected void bind(@NonNull final SupportSQLiteStatement statement,
          @NonNull final BabyEvent entity) {
        statement.bindString(1, entity.getId());
        statement.bindString(2, entity.getBabyId());
        final String _tmp = __converters.fromEventType(entity.getType());
        statement.bindString(3, _tmp);
        statement.bindLong(4, entity.getStartAt());
        if (entity.getEndAt() == null) {
          statement.bindNull(5);
        } else {
          statement.bindLong(5, entity.getEndAt());
        }
        final int _tmp_1 = entity.getOngoing() ? 1 : 0;
        statement.bindLong(6, _tmp_1);
        if (entity.getNote() == null) {
          statement.bindNull(7);
        } else {
          statement.bindString(7, entity.getNote());
        }
        final String _tmp_2 = __converters.fromSource(entity.getSource());
        statement.bindString(8, _tmp_2);
        statement.bindLong(9, entity.getCreatedAt());
        statement.bindLong(10, entity.getUpdatedAt());
        final String _tmp_3 = __converters.fromFeedMethod(entity.getFeedMethod());
        if (_tmp_3 == null) {
          statement.bindNull(11);
        } else {
          statement.bindString(11, _tmp_3);
        }
        if (entity.getVolumeMl() == null) {
          statement.bindNull(12);
        } else {
          statement.bindLong(12, entity.getVolumeMl());
        }
        final String _tmp_4 = __converters.fromBreastSide(entity.getBreastSide());
        if (_tmp_4 == null) {
          statement.bindNull(13);
        } else {
          statement.bindString(13, _tmp_4);
        }
        statement.bindString(14, entity.getId());
      }
    };
  }

  @Override
  public void insert(final BabyEvent event) {
    __db.assertNotSuspendingTransaction();
    __db.beginTransaction();
    try {
      __insertionAdapterOfBabyEvent.insert(event);
      __db.setTransactionSuccessful();
    } finally {
      __db.endTransaction();
    }
  }

  @Override
  public void delete(final BabyEvent event) {
    __db.assertNotSuspendingTransaction();
    __db.beginTransaction();
    try {
      __deletionAdapterOfBabyEvent.handle(event);
      __db.setTransactionSuccessful();
    } finally {
      __db.endTransaction();
    }
  }

  @Override
  public void update(final BabyEvent event) {
    __db.assertNotSuspendingTransaction();
    __db.beginTransaction();
    try {
      __updateAdapterOfBabyEvent.handle(event);
      __db.setTransactionSuccessful();
    } finally {
      __db.endTransaction();
    }
  }

  @Override
  public BabyEvent findOngoing(final String babyId) {
    final String _sql = "SELECT * FROM event WHERE babyId = ? AND ongoing = 1 LIMIT 1";
    final RoomSQLiteQuery _statement = RoomSQLiteQuery.acquire(_sql, 1);
    int _argIndex = 1;
    _statement.bindString(_argIndex, babyId);
    __db.assertNotSuspendingTransaction();
    final Cursor _cursor = DBUtil.query(__db, _statement, false, null);
    try {
      final int _cursorIndexOfId = CursorUtil.getColumnIndexOrThrow(_cursor, "id");
      final int _cursorIndexOfBabyId = CursorUtil.getColumnIndexOrThrow(_cursor, "babyId");
      final int _cursorIndexOfType = CursorUtil.getColumnIndexOrThrow(_cursor, "type");
      final int _cursorIndexOfStartAt = CursorUtil.getColumnIndexOrThrow(_cursor, "startAt");
      final int _cursorIndexOfEndAt = CursorUtil.getColumnIndexOrThrow(_cursor, "endAt");
      final int _cursorIndexOfOngoing = CursorUtil.getColumnIndexOrThrow(_cursor, "ongoing");
      final int _cursorIndexOfNote = CursorUtil.getColumnIndexOrThrow(_cursor, "note");
      final int _cursorIndexOfSource = CursorUtil.getColumnIndexOrThrow(_cursor, "source");
      final int _cursorIndexOfCreatedAt = CursorUtil.getColumnIndexOrThrow(_cursor, "createdAt");
      final int _cursorIndexOfUpdatedAt = CursorUtil.getColumnIndexOrThrow(_cursor, "updatedAt");
      final int _cursorIndexOfFeedMethod = CursorUtil.getColumnIndexOrThrow(_cursor, "feed_method");
      final int _cursorIndexOfVolumeMl = CursorUtil.getColumnIndexOrThrow(_cursor, "volume_ml");
      final int _cursorIndexOfBreastSide = CursorUtil.getColumnIndexOrThrow(_cursor, "breast_side");
      final BabyEvent _result;
      if (_cursor.moveToFirst()) {
        final String _tmpId;
        _tmpId = _cursor.getString(_cursorIndexOfId);
        final String _tmpBabyId;
        _tmpBabyId = _cursor.getString(_cursorIndexOfBabyId);
        final EventType _tmpType;
        final String _tmp;
        _tmp = _cursor.getString(_cursorIndexOfType);
        _tmpType = __converters.toEventType(_tmp);
        final long _tmpStartAt;
        _tmpStartAt = _cursor.getLong(_cursorIndexOfStartAt);
        final Long _tmpEndAt;
        if (_cursor.isNull(_cursorIndexOfEndAt)) {
          _tmpEndAt = null;
        } else {
          _tmpEndAt = _cursor.getLong(_cursorIndexOfEndAt);
        }
        final boolean _tmpOngoing;
        final int _tmp_1;
        _tmp_1 = _cursor.getInt(_cursorIndexOfOngoing);
        _tmpOngoing = _tmp_1 != 0;
        final String _tmpNote;
        if (_cursor.isNull(_cursorIndexOfNote)) {
          _tmpNote = null;
        } else {
          _tmpNote = _cursor.getString(_cursorIndexOfNote);
        }
        final RecordSource _tmpSource;
        final String _tmp_2;
        _tmp_2 = _cursor.getString(_cursorIndexOfSource);
        _tmpSource = __converters.toSource(_tmp_2);
        final long _tmpCreatedAt;
        _tmpCreatedAt = _cursor.getLong(_cursorIndexOfCreatedAt);
        final long _tmpUpdatedAt;
        _tmpUpdatedAt = _cursor.getLong(_cursorIndexOfUpdatedAt);
        final FeedMethod _tmpFeedMethod;
        final String _tmp_3;
        if (_cursor.isNull(_cursorIndexOfFeedMethod)) {
          _tmp_3 = null;
        } else {
          _tmp_3 = _cursor.getString(_cursorIndexOfFeedMethod);
        }
        _tmpFeedMethod = __converters.toFeedMethod(_tmp_3);
        final Integer _tmpVolumeMl;
        if (_cursor.isNull(_cursorIndexOfVolumeMl)) {
          _tmpVolumeMl = null;
        } else {
          _tmpVolumeMl = _cursor.getInt(_cursorIndexOfVolumeMl);
        }
        final BreastSide _tmpBreastSide;
        final String _tmp_4;
        if (_cursor.isNull(_cursorIndexOfBreastSide)) {
          _tmp_4 = null;
        } else {
          _tmp_4 = _cursor.getString(_cursorIndexOfBreastSide);
        }
        _tmpBreastSide = __converters.toBreastSide(_tmp_4);
        _result = new BabyEvent(_tmpId,_tmpBabyId,_tmpType,_tmpStartAt,_tmpEndAt,_tmpOngoing,_tmpNote,_tmpSource,_tmpCreatedAt,_tmpUpdatedAt,_tmpFeedMethod,_tmpVolumeMl,_tmpBreastSide);
      } else {
        _result = null;
      }
      return _result;
    } finally {
      _cursor.close();
      _statement.release();
    }
  }

  @Override
  public List<BabyEvent> allEvents(final String babyId) {
    final String _sql = "SELECT * FROM event WHERE babyId = ? ORDER BY startAt ASC";
    final RoomSQLiteQuery _statement = RoomSQLiteQuery.acquire(_sql, 1);
    int _argIndex = 1;
    _statement.bindString(_argIndex, babyId);
    __db.assertNotSuspendingTransaction();
    final Cursor _cursor = DBUtil.query(__db, _statement, false, null);
    try {
      final int _cursorIndexOfId = CursorUtil.getColumnIndexOrThrow(_cursor, "id");
      final int _cursorIndexOfBabyId = CursorUtil.getColumnIndexOrThrow(_cursor, "babyId");
      final int _cursorIndexOfType = CursorUtil.getColumnIndexOrThrow(_cursor, "type");
      final int _cursorIndexOfStartAt = CursorUtil.getColumnIndexOrThrow(_cursor, "startAt");
      final int _cursorIndexOfEndAt = CursorUtil.getColumnIndexOrThrow(_cursor, "endAt");
      final int _cursorIndexOfOngoing = CursorUtil.getColumnIndexOrThrow(_cursor, "ongoing");
      final int _cursorIndexOfNote = CursorUtil.getColumnIndexOrThrow(_cursor, "note");
      final int _cursorIndexOfSource = CursorUtil.getColumnIndexOrThrow(_cursor, "source");
      final int _cursorIndexOfCreatedAt = CursorUtil.getColumnIndexOrThrow(_cursor, "createdAt");
      final int _cursorIndexOfUpdatedAt = CursorUtil.getColumnIndexOrThrow(_cursor, "updatedAt");
      final int _cursorIndexOfFeedMethod = CursorUtil.getColumnIndexOrThrow(_cursor, "feed_method");
      final int _cursorIndexOfVolumeMl = CursorUtil.getColumnIndexOrThrow(_cursor, "volume_ml");
      final int _cursorIndexOfBreastSide = CursorUtil.getColumnIndexOrThrow(_cursor, "breast_side");
      final List<BabyEvent> _result = new ArrayList<BabyEvent>(_cursor.getCount());
      while (_cursor.moveToNext()) {
        final BabyEvent _item;
        final String _tmpId;
        _tmpId = _cursor.getString(_cursorIndexOfId);
        final String _tmpBabyId;
        _tmpBabyId = _cursor.getString(_cursorIndexOfBabyId);
        final EventType _tmpType;
        final String _tmp;
        _tmp = _cursor.getString(_cursorIndexOfType);
        _tmpType = __converters.toEventType(_tmp);
        final long _tmpStartAt;
        _tmpStartAt = _cursor.getLong(_cursorIndexOfStartAt);
        final Long _tmpEndAt;
        if (_cursor.isNull(_cursorIndexOfEndAt)) {
          _tmpEndAt = null;
        } else {
          _tmpEndAt = _cursor.getLong(_cursorIndexOfEndAt);
        }
        final boolean _tmpOngoing;
        final int _tmp_1;
        _tmp_1 = _cursor.getInt(_cursorIndexOfOngoing);
        _tmpOngoing = _tmp_1 != 0;
        final String _tmpNote;
        if (_cursor.isNull(_cursorIndexOfNote)) {
          _tmpNote = null;
        } else {
          _tmpNote = _cursor.getString(_cursorIndexOfNote);
        }
        final RecordSource _tmpSource;
        final String _tmp_2;
        _tmp_2 = _cursor.getString(_cursorIndexOfSource);
        _tmpSource = __converters.toSource(_tmp_2);
        final long _tmpCreatedAt;
        _tmpCreatedAt = _cursor.getLong(_cursorIndexOfCreatedAt);
        final long _tmpUpdatedAt;
        _tmpUpdatedAt = _cursor.getLong(_cursorIndexOfUpdatedAt);
        final FeedMethod _tmpFeedMethod;
        final String _tmp_3;
        if (_cursor.isNull(_cursorIndexOfFeedMethod)) {
          _tmp_3 = null;
        } else {
          _tmp_3 = _cursor.getString(_cursorIndexOfFeedMethod);
        }
        _tmpFeedMethod = __converters.toFeedMethod(_tmp_3);
        final Integer _tmpVolumeMl;
        if (_cursor.isNull(_cursorIndexOfVolumeMl)) {
          _tmpVolumeMl = null;
        } else {
          _tmpVolumeMl = _cursor.getInt(_cursorIndexOfVolumeMl);
        }
        final BreastSide _tmpBreastSide;
        final String _tmp_4;
        if (_cursor.isNull(_cursorIndexOfBreastSide)) {
          _tmp_4 = null;
        } else {
          _tmp_4 = _cursor.getString(_cursorIndexOfBreastSide);
        }
        _tmpBreastSide = __converters.toBreastSide(_tmp_4);
        _item = new BabyEvent(_tmpId,_tmpBabyId,_tmpType,_tmpStartAt,_tmpEndAt,_tmpOngoing,_tmpNote,_tmpSource,_tmpCreatedAt,_tmpUpdatedAt,_tmpFeedMethod,_tmpVolumeMl,_tmpBreastSide);
        _result.add(_item);
      }
      return _result;
    } finally {
      _cursor.close();
      _statement.release();
    }
  }

  @NonNull
  public static List<Class<?>> getRequiredConverters() {
    return Collections.emptyList();
  }
}
