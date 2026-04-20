package com.rekindle.app.data.di;

import com.rekindle.app.data.api.RekindleApi;
import dagger.internal.DaggerGenerated;
import dagger.internal.Factory;
import dagger.internal.Preconditions;
import dagger.internal.QualifierMetadata;
import dagger.internal.ScopeMetadata;
import javax.annotation.processing.Generated;
import javax.inject.Provider;
import retrofit2.Retrofit;

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
public final class NetworkModule_ProvideRekindleApiFactory implements Factory<RekindleApi> {
  private final Provider<Retrofit> retrofitProvider;

  public NetworkModule_ProvideRekindleApiFactory(Provider<Retrofit> retrofitProvider) {
    this.retrofitProvider = retrofitProvider;
  }

  @Override
  public RekindleApi get() {
    return provideRekindleApi(retrofitProvider.get());
  }

  public static NetworkModule_ProvideRekindleApiFactory create(
      Provider<Retrofit> retrofitProvider) {
    return new NetworkModule_ProvideRekindleApiFactory(retrofitProvider);
  }

  public static RekindleApi provideRekindleApi(Retrofit retrofit) {
    return Preconditions.checkNotNullFromProvides(NetworkModule.INSTANCE.provideRekindleApi(retrofit));
  }
}
