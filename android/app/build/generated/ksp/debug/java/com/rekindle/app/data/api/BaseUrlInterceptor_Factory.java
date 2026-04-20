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
public final class BaseUrlInterceptor_Factory implements Factory<BaseUrlInterceptor> {
  private final Provider<PrefsStore> prefsProvider;

  public BaseUrlInterceptor_Factory(Provider<PrefsStore> prefsProvider) {
    this.prefsProvider = prefsProvider;
  }

  @Override
  public BaseUrlInterceptor get() {
    return newInstance(prefsProvider.get());
  }

  public static BaseUrlInterceptor_Factory create(Provider<PrefsStore> prefsProvider) {
    return new BaseUrlInterceptor_Factory(prefsProvider);
  }

  public static BaseUrlInterceptor newInstance(PrefsStore prefs) {
    return new BaseUrlInterceptor(prefs);
  }
}
