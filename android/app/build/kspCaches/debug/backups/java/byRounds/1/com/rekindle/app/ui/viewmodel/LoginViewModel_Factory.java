package com.rekindle.app.ui.viewmodel;

import com.rekindle.app.core.prefs.PrefsStore;
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
public final class LoginViewModel_Factory implements Factory<LoginViewModel> {
  private final Provider<AuthRepository> authRepoProvider;

  private final Provider<PrefsStore> prefsProvider;

  public LoginViewModel_Factory(Provider<AuthRepository> authRepoProvider,
      Provider<PrefsStore> prefsProvider) {
    this.authRepoProvider = authRepoProvider;
    this.prefsProvider = prefsProvider;
  }

  @Override
  public LoginViewModel get() {
    return newInstance(authRepoProvider.get(), prefsProvider.get());
  }

  public static LoginViewModel_Factory create(Provider<AuthRepository> authRepoProvider,
      Provider<PrefsStore> prefsProvider) {
    return new LoginViewModel_Factory(authRepoProvider, prefsProvider);
  }

  public static LoginViewModel newInstance(AuthRepository authRepo, PrefsStore prefs) {
    return new LoginViewModel(authRepo, prefs);
  }
}
