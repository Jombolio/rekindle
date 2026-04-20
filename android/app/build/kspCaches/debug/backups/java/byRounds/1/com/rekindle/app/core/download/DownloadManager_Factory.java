package com.rekindle.app.core.download;

import android.content.Context;
import com.rekindle.app.data.db.DownloadDao;
import dagger.internal.DaggerGenerated;
import dagger.internal.Factory;
import dagger.internal.QualifierMetadata;
import dagger.internal.ScopeMetadata;
import javax.annotation.processing.Generated;
import javax.inject.Provider;
import okhttp3.OkHttpClient;

@ScopeMetadata("javax.inject.Singleton")
@QualifierMetadata("dagger.hilt.android.qualifiers.ApplicationContext")
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
public final class DownloadManager_Factory implements Factory<DownloadManager> {
  private final Provider<Context> contextProvider;

  private final Provider<OkHttpClient> okHttpClientProvider;

  private final Provider<DownloadDao> downloadDaoProvider;

  public DownloadManager_Factory(Provider<Context> contextProvider,
      Provider<OkHttpClient> okHttpClientProvider, Provider<DownloadDao> downloadDaoProvider) {
    this.contextProvider = contextProvider;
    this.okHttpClientProvider = okHttpClientProvider;
    this.downloadDaoProvider = downloadDaoProvider;
  }

  @Override
  public DownloadManager get() {
    return newInstance(contextProvider.get(), okHttpClientProvider.get(), downloadDaoProvider.get());
  }

  public static DownloadManager_Factory create(Provider<Context> contextProvider,
      Provider<OkHttpClient> okHttpClientProvider, Provider<DownloadDao> downloadDaoProvider) {
    return new DownloadManager_Factory(contextProvider, okHttpClientProvider, downloadDaoProvider);
  }

  public static DownloadManager newInstance(Context context, OkHttpClient okHttpClient,
      DownloadDao downloadDao) {
    return new DownloadManager(context, okHttpClient, downloadDao);
  }
}
