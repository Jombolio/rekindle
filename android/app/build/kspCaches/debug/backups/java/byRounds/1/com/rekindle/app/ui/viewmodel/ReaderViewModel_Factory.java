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
public final class ReaderViewModel_Factory implements Factory<ReaderViewModel> {
  private final Provider<SavedStateHandle> savedStateHandleProvider;

  private final Provider<MediaRepository> repoProvider;

  private final Provider<DownloadRepository> downloadRepoProvider;

  private final Provider<PrefsStore> prefsProvider;

  public ReaderViewModel_Factory(Provider<SavedStateHandle> savedStateHandleProvider,
      Provider<MediaRepository> repoProvider, Provider<DownloadRepository> downloadRepoProvider,
      Provider<PrefsStore> prefsProvider) {
    this.savedStateHandleProvider = savedStateHandleProvider;
    this.repoProvider = repoProvider;
    this.downloadRepoProvider = downloadRepoProvider;
    this.prefsProvider = prefsProvider;
  }

  @Override
  public ReaderViewModel get() {
    return newInstance(savedStateHandleProvider.get(), repoProvider.get(), downloadRepoProvider.get(), prefsProvider.get());
  }

  public static ReaderViewModel_Factory create(Provider<SavedStateHandle> savedStateHandleProvider,
      Provider<MediaRepository> repoProvider, Provider<DownloadRepository> downloadRepoProvider,
      Provider<PrefsStore> prefsProvider) {
    return new ReaderViewModel_Factory(savedStateHandleProvider, repoProvider, downloadRepoProvider, prefsProvider);
  }

  public static ReaderViewModel newInstance(SavedStateHandle savedStateHandle, MediaRepository repo,
      DownloadRepository downloadRepo, PrefsStore prefs) {
    return new ReaderViewModel(savedStateHandle, repo, downloadRepo, prefs);
  }
}
