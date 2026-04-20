package com.rekindle.app.data.db

import androidx.room.Database
import androidx.room.RoomDatabase

@Database(
    entities = [ProgressQueueEntity::class, DownloadEntity::class],
    version = 1,
    exportSchema = false,
)
abstract class AppDatabase : RoomDatabase() {
    abstract fun progressQueueDao(): ProgressQueueDao
    abstract fun downloadDao(): DownloadDao
}
