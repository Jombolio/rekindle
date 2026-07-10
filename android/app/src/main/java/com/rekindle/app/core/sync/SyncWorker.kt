package com.rekindle.app.core.sync

import android.content.Context
import androidx.hilt.work.HiltWorker
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.rekindle.app.data.repository.MediaRepository
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject

@HiltWorker
class SyncWorker @AssistedInject constructor(
    @Assisted context: Context,
    @Assisted params: WorkerParameters,
    private val mediaRepository: MediaRepository,
) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        // syncAllPending swallows per-row failures, so it rarely throws; ask it
        // whether anything is still unsynced and let WorkManager retry (with
        // backoff) when the server was unreachable, instead of always reporting
        // success and never retrying.
        return runCatching { mediaRepository.syncAllPending() }
            .fold(
                onSuccess = { allSynced -> if (allSynced) Result.success() else Result.retry() },
                onFailure = { Result.retry() },
            )
    }

    companion object {
        private const val WORK_NAME = "rekindle_sync"

        fun enqueue(context: Context) {
            WorkManager.getInstance(context).enqueueUniqueWork(
                WORK_NAME,
                ExistingWorkPolicy.REPLACE,
                OneTimeWorkRequestBuilder<SyncWorker>().build(),
            )
        }
    }
}
