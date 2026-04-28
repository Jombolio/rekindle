package com.rekindle.app.data.di

import android.content.Context
import androidx.room.Room
import com.rekindle.app.data.db.AppDatabase
import com.rekindle.app.data.db.DownloadDao
import com.rekindle.app.data.db.FolderDownloadDao
import com.rekindle.app.data.db.ProgressQueueDao
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object DatabaseModule {

    @Provides
    @Singleton
    fun provideDatabase(@ApplicationContext context: Context): AppDatabase =
        Room.databaseBuilder(context, AppDatabase::class.java, "rekindle.db")
            .fallbackToDestructiveMigration()
            .build()

    @Provides
    fun provideProgressQueueDao(db: AppDatabase): ProgressQueueDao =
        db.progressQueueDao()

    @Provides
    fun provideDownloadDao(db: AppDatabase): DownloadDao =
        db.downloadDao()

    @Provides
    fun provideFolderDownloadDao(db: AppDatabase): FolderDownloadDao =
        db.folderDownloadDao()
}
