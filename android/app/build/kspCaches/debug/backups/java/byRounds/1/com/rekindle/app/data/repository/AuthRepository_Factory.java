package com.rekindle.app.data.repository;

import com.rekindle.app.core.prefs.PrefsStore;
import com.rekindle.app.data.api.RekindleApi;
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
public final class AuthRepository_Factory implements Factory<AuthRepository> {
  private final Provider<RekindleApi> apiProvider;

  private final Provider<PrefsStore> prefsProvider;

  public AuthRepository_Factory(Provider<RekindleApi> apiProvider,
      Provider<PrefsStore> prefsProvider) {
    this.apiProvider = apiProvider;
    this.prefsProvider = prefsProvider;
  }

  @Override
  public AuthRepository get() {
    return newInstance(apiProvider.get(), prefsProvider.get());
  }

  public static AuthRepository_Factory create(Provider<RekindleApi> apiProvider,
      Provider<PrefsStore> prefsProvider) {
    return new AuthRepository_Factory(apiProvider, prefsProvider);
  }

  public static AuthRepository newInstance(RekindleApi api, PrefsStore prefs) {
    return new AuthRepository(api, prefs);
  }
}
