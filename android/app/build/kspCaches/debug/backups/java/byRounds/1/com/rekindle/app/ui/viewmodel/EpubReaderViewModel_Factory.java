package com.rekindle.app.ui.viewmodel;

import androidx.lifecycle.SavedStateHandle;
import com.rekindle.app.core.prefs.PrefsStore;
import com.rekindle.app.data.repository.DownloadRepository;
import com.rekindle.app.data.repository.MediaRepository;
import dagger.internal.DaggerGenerated;
import dagger.internal.Factory;
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
public final class EpubReaderViewModel_Factory implements Factory<EpubReaderViewModel> {
  private final Provider<SavedStateHandle> savedStateHandleProvider;

  private final Provider<DownloadRepository> downloadRepoProvider;

  private final Provider<MediaRepository> mediaRepoProvider;

  private final Provider<PrefsStore> prefsProvider;

  public EpubReaderViewModel_Factory(Provider<SavedStateHandle> savedStateHandleProvider,
      Provider<DownloadRepository> downloadRepoProvider,
      Provider<MediaRepository> mediaRepoProvider, Provider<PrefsStore> prefsProvider) {
    this.savedStateHandleProvider = savedStateHandleProvider;
    this.downloadRepoProvider = downloadRepoProvider;
    this.mediaRepoProvider = mediaRepoProvider;
    this.prefsProvider = prefsProvider;
  }

  @Override
  public EpubReaderViewModel get() {
    return newInstance(savedStateHandleProvider.get(), downloadRepoProvider.get(), mediaRepoProvider.get(), prefsProvider.get());
  }

  public static EpubReaderViewModel_Factory create(
      Provider<SavedStateHandle> savedStateHandleProvider,
      Provider<DownloadRepository> downloadRepoProvider,
      Provider<MediaRepository> mediaRepoProvider, Provider<PrefsStore> prefsProvider) {
    return new EpubReaderViewModel_Factory(savedStateHandleProvider, downloadRepoProvider, mediaRepoProvider, prefsProvider);
  }

  public static EpubReaderViewModel newInstance(SavedStateHandle savedStateHandle,
      DownloadRepository downloadRepo, MediaRepository mediaRepo, PrefsStore prefs) {
    return new EpubReaderViewModel(savedStateHandle, downloadRepo, mediaRepo, prefs);
  }
}
