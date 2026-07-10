package com.rekindle.app.data.db

import androidx.room.ColumnInfo
import androidx.room.Dao
import androidx.room.Entity
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.PrimaryKey
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

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

    @Query("SELECT * FROM progress_queue WHERE media_id IN (:mediaIds)")
    suspend fun getByMediaIds(mediaIds: List<String>): List<ProgressQueueEntity>

    /** Live variant: Room re-emits whenever progress_queue changes, so list
     *  screens see fresh badges the moment the reader writes progress. */
    @Query("SELECT * FROM progress_queue WHERE media_id IN (:mediaIds)")
    fun observeByMediaIds(mediaIds: List<String>): Flow<List<ProgressQueueEntity>>

    @Query("SELECT * FROM progress_queue WHERE synced = 0")
    suspend fun getUnsynced(): List<ProgressQueueEntity>

    @Query("UPDATE progress_queue SET synced = 1 WHERE media_id = :mediaId")
    suspend fun markSynced(mediaId: String)

    /**
     * Marks a row synced only if it still matches the snapshot that was sent to
     * the server. A concurrent page turn writes a new [lastReadAt], so this
     * no-ops and the newer progress stays queued for the next sync.
     */
    @Query(
        "UPDATE progress_queue SET synced = 1 WHERE media_id = :mediaId " +
            "AND current_page = :currentPage AND is_completed = :isCompleted AND last_read_at = :lastReadAt",
    )
    suspend fun markSyncedIfUnchanged(
        mediaId: String,
        currentPage: Int,
        isCompleted: Boolean,
        lastReadAt: Long,
    )
}
