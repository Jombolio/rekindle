package com.rekindle.app.data.db

import androidx.room.ColumnInfo
import androidx.room.Dao
import androidx.room.Entity
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.PrimaryKey
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

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

    @Query("SELECT media_id FROM downloads WHERE status = 'COMPLETE'")
    suspend fun getAllCompleteMediaIds(): List<String>

    @Query("SELECT * FROM downloads WHERE status = 'COMPLETE' ORDER BY title COLLATE NOCASE")
    fun observeCompleted(): Flow<List<DownloadEntity>>

    @Query("SELECT * FROM downloads")
    suspend fun getAllDownloads(): List<DownloadEntity>

    @Query("DELETE FROM downloads WHERE media_id = :mediaId")
    suspend fun delete(mediaId: String)

    @Query("DELETE FROM downloads")
    suspend fun deleteAll()
}

// ---------------------------------------------------------------------------
// Folder-level download persistence
// ---------------------------------------------------------------------------

@Entity(tableName = "folder_downloads")
data class FolderDownloadEntity(
    @PrimaryKey @ColumnInfo(name = "folder_id") val folderId: String,
    @ColumnInfo(name = "status") val status: String,
    @ColumnInfo(name = "total") val total: Int,
    @ColumnInfo(name = "completed") val completed: Int,
)

@Dao
interface FolderDownloadDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: FolderDownloadEntity)

    @Query("SELECT * FROM folder_downloads WHERE folder_id = :folderId LIMIT 1")
    suspend fun getByFolderId(folderId: String): FolderDownloadEntity?

    @Query("DELETE FROM folder_downloads")
    suspend fun deleteAll()
}
