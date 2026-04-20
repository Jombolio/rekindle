package com.rekindle.app.data.repository;

import com.rekindle.app.data.api.RekindleApi;
import com.rekindle.app.data.db.ProgressQueueDao;
import dagger.internal.DaggerGenerated;
import dagger.internal.Factory;
import dagger.internal.QualifierMetadata;
import dagger.internal.ScopeMetadata;
import javax.annotation.processing.Generated;
import javax.inject.Provider;

@ScopeMetadata("javax.inject.Singleton")
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
public final class MediaRepository_Factory implements Factory<MediaRepository> {
  private final Provider<RekindleApi> apiProvider;

  private final Provider<ProgressQueueDao> progressDaoProvider;

  public MediaRepository_Factory(Provider<RekindleApi> apiProvider,
      Provider<ProgressQueueDao> progressDaoProvider) {
    this.apiProvider = apiProvider;
    this.progressDaoProvider = progressDaoProvider;
  }

  @Override
  public MediaRepository get() {
    return newInstance(apiProvider.get(), progressDaoProvider.get());
  }

  public static MediaRepository_Factory create(Provider<RekindleApi> apiProvider,
      Provider<ProgressQueueDao> progressDaoProvider) {
    return new MediaRepository_Factory(apiProvider, progressDaoProvider);
  }

  public static MediaRepository newInstance(RekindleApi api, ProgressQueueDao progressDao) {
    return new MediaRepository(api, progressDao);
  }
}
