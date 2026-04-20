package com.rekindle.app.ui.viewmodel;

import android.content.Context;
import com.rekindle.app.core.prefs.PrefsStore;
import dagger.internal.DaggerGenerated;
import dagger.internal.Factory;
import dagger.internal.QualifierMetadata;
import dagger.internal.ScopeMetadata;
import javax.annotation.processing.Generated;
import javax.inject.Provider;

@ScopeMetadata
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
public final class SettingsViewModel_Factory implements Factory<SettingsViewModel> {
  private final Provider<PrefsStore> prefsProvider;

  private final Provider<Context> contextProvider;

  public SettingsViewModel_Factory(Provider<PrefsStore> prefsProvider,
      Provider<Context> contextProvider) {
    this.prefsProvider = prefsProvider;
    this.contextProvider = contextProvider;
  }

  @Override
  public SettingsViewModel get() {
    return newInstance(prefsProvider.get(), contextProvider.get());
  }

  public static SettingsViewModel_Factory create(Provider<PrefsStore> prefsProvider,
      Provider<Context> contextProvider) {
    return new SettingsViewModel_Factory(prefsProvider, contextProvider);
  }

  public static SettingsViewModel newInstance(PrefsStore prefs, Context context) {
    return new SettingsViewModel(prefs, context);
  }
}
