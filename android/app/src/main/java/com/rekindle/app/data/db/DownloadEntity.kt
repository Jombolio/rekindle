package com.rekindle.app.data.db

import androidx.room.ColumnInfo
import androidx.room.Dao
import androidx.room.Entity
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.PrimaryKey
import androidx.room.Query

@Entity(tableName = "downloads")
data class DownloadEntity(
    @PrimaryKey @ColumnInfo(name = "media_id") val mediaId: String,
    @ColumnInfo(name = "status") val status: String,
    @ColumnInfo(name = "progress") val progress: Float,
    @ColumnInfo(name = "local_path") val localPath: String?,
    @ColumnInfo(name = "format") val format: String,
    @ColumnInfo(name = "title") val title: String,
)

@Dao
interface DownloadDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: DownloadEntity)

    @Query("SELECT * FROM downloads WHERE media_id = :mediaId LIMIT 1")
    suspend fun getByMediaId(mediaId: String): DownloadEntity?

    @Query("DELETE FROM downloads WHERE media_id = :mediaId")
    suspend fun delete(mediaId: String)
}
