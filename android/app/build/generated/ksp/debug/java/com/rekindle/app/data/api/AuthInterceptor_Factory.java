package com.rekindle.app.data.api;

import com.rekindle.app.core.prefs.PrefsStore;
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
public final class AuthInterceptor_Factory implements Factory<AuthInterceptor> {
  private final Provider<PrefsStore> prefsProvider;

  public AuthInterceptor_Factory(Provider<PrefsStore> prefsProvider) {
    this.prefsProvider = prefsProvider;
  }

  @Override
  public AuthInterceptor get() {
    return newInstance(prefsProvider.get());
  }

  public static AuthInterceptor_Factory create(Provider<PrefsStore> prefsProvider) {
    return new AuthInterceptor_Factory(prefsProvider);
  }

  public static AuthInterceptor newInstance(PrefsStore prefs) {
    return new AuthInterceptor(prefs);
  }
}
