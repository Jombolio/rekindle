package com.rekindle.app.data.db

import androidx.room.Database
import androidx.room.RoomDatabase

@Database(
    entities = [ProgressQueueEntity::class, DownloadEntity::class, FolderDownloadEntity::class],
    version = 2,
    exportSchema = false,
)
abstract class AppDatabase : RoomDatabase() {
    abstract fun progressQueueDao(): ProgressQueueDao
    abstract fun downloadDao(): DownloadDao
    abstract fun folderDownloadDao(): FolderDownloadDao
}
