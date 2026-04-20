package com.rekindle.app.core.prefs;

import android.content.Context;
import dagger.internal.DaggerGenerated;
import dagger.internal.Factory;
import dagger.internal.QualifierMetadata;
import dagger.internal.ScopeMetadata;
import javax.annotation.processing.Generated;
import javax.inject.Provider;

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
public final class PrefsStore_Factory implements Factory<PrefsStore> {
  private final Provider<Context> contextProvider;

  public PrefsStore_Factory(Provider<Context> contextProvider) {
    this.contextProvider = contextProvider;
  }

  @Override
  public PrefsStore get() {
    return newInstance(contextProvider.get());
  }

  public static PrefsStore_Factory create(Provider<Context> contextProvider) {
    return new PrefsStore_Factory(contextProvider);
  }

  public static PrefsStore newInstance(Context context) {
    return new PrefsStore(context);
  }
}
