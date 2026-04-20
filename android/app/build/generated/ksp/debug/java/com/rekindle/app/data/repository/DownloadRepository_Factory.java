package com.rekindle.app.data.repository;

import com.rekindle.app.core.download.DownloadManager;
import com.rekindle.app.core.prefs.PrefsStore;
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
public final class DownloadRepository_Factory implements Factory<DownloadRepository> {
  private final Provider<DownloadManager> downloadManagerProvider;

  private final Provider<PrefsStore> prefsProvider;

  public DownloadRepository_Factory(Provider<DownloadManager> downloadManagerProvider,
      Provider<PrefsStore> prefsProvider) {
    this.downloadManagerProvider = downloadManagerProvider;
    this.prefsProvider = prefsProvider;
  }

  @Override
  public DownloadRepository get() {
    return newInstance(downloadManagerProvider.get(), prefsProvider.get());
  }

  public static DownloadRepository_Factory create(Provider<DownloadManager> downloadManagerProvider,
      Provider<PrefsStore> prefsProvider) {
    return new DownloadRepository_Factory(downloadManagerProvider, prefsProvider);
  }

  public static DownloadRepository newInstance(DownloadManager downloadManager, PrefsStore prefs) {
    return new DownloadRepository(downloadManager, prefs);
  }
}
