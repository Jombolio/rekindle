package com.rekindle.app.data.db;

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
  private volatile ProgressQueueDao _progressQueueDao;

  private volatile DownloadDao _downloadDao;

  @Override
  @NonNull
  protected SupportSQLiteOpenHelper createOpenHelper(@NonNull final DatabaseConfiguration config) {
    final SupportSQLiteOpenHelper.Callback _openCallback = new RoomOpenHelper(config, new RoomOpenHelper.Delegate(1) {
      @Override
      public void createAllTables(@NonNull final SupportSQLiteDatabase db) {
        db.execSQL("CREATE TABLE IF NOT EXISTS `progress_queue` (`media_id` TEXT NOT NULL, `current_page` INTEGER NOT NULL, `is_completed` INTEGER NOT NULL, `last_read_at` INTEGER NOT NULL, `synced` INTEGER NOT NULL, PRIMARY KEY(`media_id`))");
        db.execSQL("CREATE TABLE IF NOT EXISTS `downloads` (`media_id` TEXT NOT NULL, `status` TEXT NOT NULL, `progress` REAL NOT NULL, `local_path` TEXT, `format` TEXT NOT NULL, `title` TEXT NOT NULL, PRIMARY KEY(`media_id`))");
        db.execSQL("CREATE TABLE IF NOT EXISTS room_master_table (id INTEGER PRIMARY KEY,identity_hash TEXT)");
        db.execSQL("INSERT OR REPLACE INTO room_master_table (id,identity_hash) VALUES(42, '939cbafc977c026f42ba6f95de9427aa')");
      }

      @Override
      public void dropAllTables(@NonNull final SupportSQLiteDatabase db) {
        db.execSQL("DROP TABLE IF EXISTS `progress_queue`");
        db.execSQL("DROP TABLE IF EXISTS `downloads`");
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
        final HashMap<String, TableInfo.Column> _columnsProgressQueue = new HashMap<String, TableInfo.Column>(5);
        _columnsProgressQueue.put("media_id", new TableInfo.Column("media_id", "TEXT", true, 1, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsProgressQueue.put("current_page", new TableInfo.Column("current_page", "INTEGER", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsProgressQueue.put("is_completed", new TableInfo.Column("is_completed", "INTEGER", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsProgressQueue.put("last_read_at", new TableInfo.Column("last_read_at", "INTEGER", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsProgressQueue.put("synced", new TableInfo.Column("synced", "INTEGER", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        final HashSet<TableInfo.ForeignKey> _foreignKeysProgressQueue = new HashSet<TableInfo.ForeignKey>(0);
        final HashSet<TableInfo.Index> _indicesProgressQueue = new HashSet<TableInfo.Index>(0);
        final TableInfo _infoProgressQueue = new TableInfo("progress_queue", _columnsProgressQueue, _foreignKeysProgressQueue, _indicesProgressQueue);
        final TableInfo _existingProgressQueue = TableInfo.read(db, "progress_queue");
        if (!_infoProgressQueue.equals(_existingProgressQueue)) {
          return new RoomOpenHelper.ValidationResult(false, "progress_queue(com.rekindle.app.data.db.ProgressQueueEntity).\n"
                  + " Expected:\n" + _infoProgressQueue + "\n"
                  + " Found:\n" + _existingProgressQueue);
        }
        final HashMap<String, TableInfo.Column> _columnsDownloads = new HashMap<String, TableInfo.Column>(6);
        _columnsDownloads.put("media_id", new TableInfo.Column("media_id", "TEXT", true, 1, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsDownloads.put("status", new TableInfo.Column("status", "TEXT", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsDownloads.put("progress", new TableInfo.Column("progress", "REAL", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsDownloads.put("local_path", new TableInfo.Column("local_path", "TEXT", false, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsDownloads.put("format", new TableInfo.Column("format", "TEXT", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsDownloads.put("title", new TableInfo.Column("title", "TEXT", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        final HashSet<TableInfo.ForeignKey> _foreignKeysDownloads = new HashSet<TableInfo.ForeignKey>(0);
        final HashSet<TableInfo.Index> _indicesDownloads = new HashSet<TableInfo.Index>(0);
        final TableInfo _infoDownloads = new TableInfo("downloads", _columnsDownloads, _foreignKeysDownloads, _indicesDownloads);
        final TableInfo _existingDownloads = TableInfo.read(db, "downloads");
        if (!_infoDownloads.equals(_existingDownloads)) {
          return new RoomOpenHelper.ValidationResult(false, "downloads(com.rekindle.app.data.db.DownloadEntity).\n"
                  + " Expected:\n" + _infoDownloads + "\n"
                  + " Found:\n" + _existingDownloads);
        }
        return new RoomOpenHelper.ValidationResult(true, null);
      }
    }, "939cbafc977c026f42ba6f95de9427aa", "93a8e5903bf058b1220f466ed9fa5846");
    final SupportSQLiteOpenHelper.Configuration _sqliteConfig = SupportSQLiteOpenHelper.Configuration.builder(config.context).name(config.name).callback(_openCallback).build();
    final SupportSQLiteOpenHelper _helper = config.sqliteOpenHelperFactory.create(_sqliteConfig);
    return _helper;
  }

  @Override
  @NonNull
  protected InvalidationTracker createInvalidationTracker() {
    final HashMap<String, String> _shadowTablesMap = new HashMap<String, String>(0);
    final HashMap<String, Set<String>> _viewTables = new HashMap<String, Set<String>>(0);
    return new InvalidationTracker(this, _shadowTablesMap, _viewTables, "progress_queue","downloads");
  }

  @Override
  public void clearAllTables() {
    super.assertNotMainThread();
    final SupportSQLiteDatabase _db = super.getOpenHelper().getWritableDatabase();
    try {
      super.beginTransaction();
      _db.execSQL("DELETE FROM `progress_queue`");
      _db.execSQL("DELETE FROM `downloads`");
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
    _typeConvertersMap.put(ProgressQueueDao.class, ProgressQueueDao_Impl.getRequiredConverters());
    _typeConvertersMap.put(DownloadDao.class, DownloadDao_Impl.getRequiredConverters());
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
  public ProgressQueueDao progressQueueDao() {
    if (_progressQueueDao != null) {
      return _progressQueueDao;
    } else {
      synchronized(this) {
        if(_progressQueueDao == null) {
          _progressQueueDao = new ProgressQueueDao_Impl(this);
        }
        return _progressQueueDao;
      }
    }
  }

  @Override
  public DownloadDao downloadDao() {
    if (_downloadDao != null) {
      return _downloadDao;
    } else {
      synchronized(this) {
        if(_downloadDao == null) {
          _downloadDao = new DownloadDao_Impl(this);
        }
        return _downloadDao;
      }
    }
  }
}
