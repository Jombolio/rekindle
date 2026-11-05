package com.rekindle.app.data.db

import androidx.room.Database
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

@Database(
    entities = [ProgressQueueEntity::class, DownloadEntity::class, FolderDownloadEntity::class],
    version = 3,
    exportSchema = false,
)
abstract class AppDatabase : RoomDatabase() {
    abstract fun progressQueueDao(): ProgressQueueDao
    abstract fun downloadDao(): DownloadDao
    abstract fun folderDownloadDao(): FolderDownloadDao
}

/** Keeps queued progress and downloads, which the destructive fallback would wipe. */
val MIGRATION_2_3 = object : Migration(2, 3) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL("ALTER TABLE progress_queue ADD COLUMN position_fraction REAL")
    }
}
