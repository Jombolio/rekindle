package com.rekindle.app.data.db

import androidx.room.ColumnInfo
import androidx.room.Dao
import androidx.room.Entity
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.PrimaryKey
import androidx.room.Query

@Entity(tableName = "progress_queue")
data class ProgressQueueEntity(
    @PrimaryKey @ColumnInfo(name = "media_id") val mediaId: String,
    @ColumnInfo(name = "current_page") val currentPage: Int,
    @ColumnInfo(name = "is_completed") val isCompleted: Boolean,
    @ColumnInfo(name = "last_read_at") val lastReadAt: Long,
    @ColumnInfo(name = "synced") val synced: Boolean = false,
)

@Dao
interface ProgressQueueDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: ProgressQueueEntity)

    @Query("SELECT * FROM progress_queue WHERE media_id = :mediaId LIMIT 1")
    suspend fun getByMediaId(mediaId: String): ProgressQueueEntity?

    @Query("SELECT * FROM progress_queue WHERE synced = 0")
    suspend fun getUnsynced(): List<ProgressQueueEntity>

    @Query("UPDATE progress_queue SET synced = 1 WHERE media_id = :mediaId")
    suspend fun markSynced(mediaId: String)
}
