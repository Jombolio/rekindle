package com.rekindle.app.ui.viewmodel;

import com.rekindle.app.core.prefs.PrefsStore;
import com.rekindle.app.data.api.RekindleApi;
import com.rekindle.app.data.repository.AuthRepository;
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
public final class LibraryViewModel_Factory implements Factory<LibraryViewModel> {
  private final Provider<RekindleApi> apiProvider;

  private final Provider<AuthRepository> authRepoProvider;

  private final Provider<PrefsStore> prefsProvider;

  public LibraryViewModel_Factory(Provider<RekindleApi> apiProvider,
      Provider<AuthRepository> authRepoProvider, Provider<PrefsStore> prefsProvider) {
    this.apiProvider = apiProvider;
    this.authRepoProvider = authRepoProvider;
    this.prefsProvider = prefsProvider;
  }

  @Override
  public LibraryViewModel get() {
    return newInstance(apiProvider.get(), authRepoProvider.get(), prefsProvider.get());
  }

  public static LibraryViewModel_Factory create(Provider<RekindleApi> apiProvider,
      Provider<AuthRepository> authRepoProvider, Provider<PrefsStore> prefsProvider) {
    return new LibraryViewModel_Factory(apiProvider, authRepoProvider, prefsProvider);
  }

  public static LibraryViewModel newInstance(RekindleApi api, AuthRepository authRepo,
      PrefsStore prefs) {
    return new LibraryViewModel(api, authRepo, prefs);
  }
}
