package com.rekindle.app;

import androidx.hilt.work.HiltWorkerFactory;
import dagger.MembersInjector;
import dagger.internal.DaggerGenerated;
import dagger.internal.InjectedFieldSignature;
import dagger.internal.QualifierMetadata;
import javax.annotation.processing.Generated;
import javax.inject.Provider;

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
public final class RekindleApplication_MembersInjector implements MembersInjector<RekindleApplication> {
  private final Provider<HiltWorkerFactory> workerFactoryProvider;

  public RekindleApplication_MembersInjector(Provider<HiltWorkerFactory> workerFactoryProvider) {
    this.workerFactoryProvider = workerFactoryProvider;
  }

  public static MembersInjector<RekindleApplication> create(
      Provider<HiltWorkerFactory> workerFactoryProvider) {
    return new RekindleApplication_MembersInjector(workerFactoryProvider);
  }

  @Override
  public void injectMembers(RekindleApplication instance) {
    injectWorkerFactory(instance, workerFactoryProvider.get());
  }

  @InjectedFieldSignature("com.rekindle.app.RekindleApplication.workerFactory")
  public static void injectWorkerFactory(RekindleApplication instance,
      HiltWorkerFactory workerFactory) {
    instance.workerFactory = workerFactory;
  }
}
