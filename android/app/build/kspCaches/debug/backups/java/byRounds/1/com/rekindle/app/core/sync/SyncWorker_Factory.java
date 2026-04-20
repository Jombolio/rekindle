package com.rekindle.app.core.sync;

import android.content.Context;
import androidx.work.WorkerParameters;
import com.rekindle.app.data.repository.MediaRepository;
import dagger.internal.DaggerGenerated;
import dagger.internal.QualifierMetadata;
import dagger.internal.ScopeMetadata;
import javax.annotation.processing.Generated;
import javax.inject.Provider;

@ScopeMetadata
@QualifierMetadata
@DaggerGenerated
@Generated(
    value = "dagger.internal.codegen.ComponentProcessor",
    comments = "https://dagger.dev"
)
@SuppressWarnings({
    "unchecked",
    "rawtypes",
    "KotlinInternal",
    "KotlinInternalInJava",
    "cast",
    "deprecation"
})
public final class SyncWorker_Factory {
  private final Provider<MediaRepository> mediaRepositoryProvider;

  public SyncWorker_Factory(Provider<MediaRepository> mediaRepositoryProvider) {
    this.mediaRepositoryProvider = mediaRepositoryProvider;
  }

  public SyncWorker get(Context context, WorkerParameters params) {
    return newInstance(context, params, mediaRepositoryProvider.get());
  }

  public static SyncWorker_Factory create(Provider<MediaRepository> mediaRepositoryProvider) {
    return new SyncWorker_Factory(mediaRepositoryProvider);
  }

  public static SyncWorker newInstance(Context context, WorkerParameters params,
      MediaRepository mediaRepository) {
    return new SyncWorker(context, params, mediaRepository);
  }
}
