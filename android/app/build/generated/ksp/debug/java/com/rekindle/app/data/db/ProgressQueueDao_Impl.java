package com.rekindle.app.data.db;

import android.database.Cursor;
import android.os.CancellationSignal;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.room.CoroutinesRoom;
import androidx.room.EntityInsertionAdapter;
import androidx.room.RoomDatabase;
import androidx.room.RoomSQLiteQuery;
import androidx.room.SharedSQLiteStatement;
import androidx.room.util.CursorUtil;
import androidx.room.util.DBUtil;
import androidx.sqlite.db.SupportSQLiteStatement;
import java.lang.Class;
import java.lang.Exception;
import java.lang.Object;
import java.lang.Override;
import java.lang.String;
import java.lang.SuppressWarnings;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.Callable;
import javax.annotation.processing.Generated;
import kotlin.Unit;
import kotlin.coroutines.Continuation;

@Generated("androidx.room.RoomProcessor")
@SuppressWarnings({"unchecked", "deprecation"})
public final class ProgressQueueDao_Impl implements ProgressQueueDao {
  private final RoomDatabase __db;

  private final EntityInsertionAdapter<ProgressQueueEntity> __insertionAdapterOfProgressQueueEntity;

  private final SharedSQLiteStatement __preparedStmtOfMarkSynced;

  public ProgressQueueDao_Impl(@NonNull final RoomDatabase __db) {
    this.__db = __db;
    this.__insertionAdapterOfProgressQueueEntity = new EntityInsertionAdapter<ProgressQueueEntity>(__db) {
      @Override
      @NonNull
      protected String createQuery() {
        return "INSERT OR REPLACE INTO `progress_queue` (`media_id`,`current_page`,`is_completed`,`last_read_at`,`synced`) VALUES (?,?,?,?,?)";
      }

      @Override
      protected void bind(@NonNull final SupportSQLiteStatement statement,
          @NonNull final ProgressQueueEntity entity) {
        statement.bindString(1, entity.getMediaId());
        statement.bindLong(2, entity.getCurrentPage());
        final int _tmp = entity.isCompleted() ? 1 : 0;
        statement.bindLong(3, _tmp);
        statement.bindLong(4, entity.getLastReadAt());
        final int _tmp_1 = entity.getSynced() ? 1 : 0;
        statement.bindLong(5, _tmp_1);
      }
    };
    this.__preparedStmtOfMarkSynced = new SharedSQLiteStatement(__db) {
      @Override
      @NonNull
      public String createQuery() {
        final String _query = "UPDATE progress_queue SET synced = 1 WHERE media_id = ?";
        return _query;
      }
    };
  }

  @Override
  public Object upsert(final ProgressQueueEntity entity,
      final Continuation<? super Unit> $completion) {
    return CoroutinesRoom.execute(__db, true, new Callable<Unit>() {
      @Override
      @NonNull
      public Unit call() throws Exception {
        __db.beginTransaction();
        try {
          __insertionAdapterOfProgressQueueEntity.insert(entity);
          __db.setTransactionSuccessful();
          return Unit.INSTANCE;
        } finally {
          __db.endTransaction();
        }
      }
    }, $completion);
  }

  @Override
  public Object markSynced(final String mediaId, final Continuation<? super Unit> $completion) {
    return CoroutinesRoom.execute(__db, true, new Callable<Unit>() {
      @Override
      @NonNull
      public Unit call() throws Exception {
        final SupportSQLiteStatement _stmt = __preparedStmtOfMarkSynced.acquire();
        int _argIndex = 1;
        _stmt.bindString(_argIndex, mediaId);
        try {
          __db.beginTransaction();
          try {
            _stmt.executeUpdateDelete();
            __db.setTransactionSuccessful();
            return Unit.INSTANCE;
          } finally {
            __db.endTransaction();
          }
        } finally {
          __preparedStmtOfMarkSynced.release(_stmt);
        }
      }
    }, $completion);
  }

  @Override
  public Object getByMediaId(final String mediaId,
      final Continuation<? super ProgressQueueEntity> $completion) {
    final String _sql = "SELECT * FROM progress_queue WHERE media_id = ? LIMIT 1";
    final RoomSQLiteQuery _statement = RoomSQLiteQuery.acquire(_sql, 1);
    int _argIndex = 1;
    _statement.bindString(_argIndex, mediaId);
    final CancellationSignal _cancellationSignal = DBUtil.createCancellationSignal();
    return CoroutinesRoom.execute(__db, false, _cancellationSignal, new Callable<ProgressQueueEntity>() {
      @Override
      @Nullable
      public ProgressQueueEntity call() throws Exception {
        final Cursor _cursor = DBUtil.query(__db, _statement, false, null);
        try {
          final int _cursorIndexOfMediaId = CursorUtil.getColumnIndexOrThrow(_cursor, "media_id");
          final int _cursorIndexOfCurrentPage = CursorUtil.getColumnIndexOrThrow(_cursor, "current_page");
          final int _cursorIndexOfIsCompleted = CursorUtil.getColumnIndexOrThrow(_cursor, "is_completed");
          final int _cursorIndexOfLastReadAt = CursorUtil.getColumnIndexOrThrow(_cursor, "last_read_at");
          final int _cursorIndexOfSynced = CursorUtil.getColumnIndexOrThrow(_cursor, "synced");
          final ProgressQueueEntity _result;
          if (_cursor.moveToFirst()) {
            final String _tmpMediaId;
            _tmpMediaId = _cursor.getString(_cursorIndexOfMediaId);
            final int _tmpCurrentPage;
            _tmpCurrentPage = _cursor.getInt(_cursorIndexOfCurrentPage);
            final boolean _tmpIsCompleted;
            final int _tmp;
            _tmp = _cursor.getInt(_cursorIndexOfIsCompleted);
            _tmpIsCompleted = _tmp != 0;
            final long _tmpLastReadAt;
            _tmpLastReadAt = _cursor.getLong(_cursorIndexOfLastReadAt);
            final boolean _tmpSynced;
            final int _tmp_1;
            _tmp_1 = _cursor.getInt(_cursorIndexOfSynced);
            _tmpSynced = _tmp_1 != 0;
            _result = new ProgressQueueEntity(_tmpMediaId,_tmpCurrentPage,_tmpIsCompleted,_tmpLastReadAt,_tmpSynced);
          } else {
            _result = null;
          }
          return _result;
        } finally {
          _cursor.close();
          _statement.release();
        }
      }
    }, $completion);
  }

  @Override
  public Object getUnsynced(final Continuation<? super List<ProgressQueueEntity>> $completion) {
    final String _sql = "SELECT * FROM progress_queue WHERE synced = 0";
    final RoomSQLiteQuery _statement = RoomSQLiteQuery.acquire(_sql, 0);
    final CancellationSignal _cancellationSignal = DBUtil.createCancellationSignal();
    return CoroutinesRoom.execute(__db, false, _cancellationSignal, new Callable<List<ProgressQueueEntity>>() {
      @Override
      @NonNull
      public List<ProgressQueueEntity> call() throws Exception {
        final Cursor _cursor = DBUtil.query(__db, _statement, false, null);
        try {
          final int _cursorIndexOfMediaId = CursorUtil.getColumnIndexOrThrow(_cursor, "media_id");
          final int _cursorIndexOfCurrentPage = CursorUtil.getColumnIndexOrThrow(_cursor, "current_page");
          final int _cursorIndexOfIsCompleted = CursorUtil.getColumnIndexOrThrow(_cursor, "is_completed");
          final int _cursorIndexOfLastReadAt = CursorUtil.getColumnIndexOrThrow(_cursor, "last_read_at");
          final int _cursorIndexOfSynced = CursorUtil.getColumnIndexOrThrow(_cursor, "synced");
          final List<ProgressQueueEntity> _result = new ArrayList<ProgressQueueEntity>(_cursor.getCount());
          while (_cursor.moveToNext()) {
            final ProgressQueueEntity _item;
            final String _tmpMediaId;
            _tmpMediaId = _cursor.getString(_cursorIndexOfMediaId);
            final int _tmpCurrentPage;
            _tmpCurrentPage = _cursor.getInt(_cursorIndexOfCurrentPage);
            final boolean _tmpIsCompleted;
            final int _tmp;
            _tmp = _cursor.getInt(_cursorIndexOfIsCompleted);
            _tmpIsCompleted = _tmp != 0;
            final long _tmpLastReadAt;
            _tmpLastReadAt = _cursor.getLong(_cursorIndexOfLastReadAt);
            final boolean _tmpSynced;
            final int _tmp_1;
            _tmp_1 = _cursor.getInt(_cursorIndexOfSynced);
            _tmpSynced = _tmp_1 != 0;
            _item = new ProgressQueueEntity(_tmpMediaId,_tmpCurrentPage,_tmpIsCompleted,_tmpLastReadAt,_tmpSynced);
            _result.add(_item);
          }
          return _result;
        } finally {
          _cursor.close();
          _statement.release();
        }
      }
    }, $completion);
  }

  @NonNull
  public static List<Class<?>> getRequiredConverters() {
    return Collections.emptyList();
  }
}
