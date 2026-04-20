package com.rekindle.app.data.di;

import com.rekindle.app.data.api.AuthInterceptor;
import com.rekindle.app.data.api.BaseUrlInterceptor;
import dagger.internal.DaggerGenerated;
import dagger.internal.Factory;
import dagger.internal.Preconditions;
import dagger.internal.QualifierMetadata;
import dagger.internal.ScopeMetadata;
import javax.annotation.processing.Generated;
import javax.inject.Provider;
import okhttp3.OkHttpClient;

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
public final class NetworkModule_ProvideOkHttpClientFactory implements Factory<OkHttpClient> {
  private final Provider<AuthInterceptor> authInterceptorProvider;

  private final Provider<BaseUrlInterceptor> baseUrlInterceptorProvider;

  public NetworkModule_ProvideOkHttpClientFactory(Provider<AuthInterceptor> authInterceptorProvider,
      Provider<BaseUrlInterceptor> baseUrlInterceptorProvider) {
    this.authInterceptorProvider = authInterceptorProvider;
    this.baseUrlInterceptorProvider = baseUrlInterceptorProvider;
  }

  @Override
  public OkHttpClient get() {
    return provideOkHttpClient(authInterceptorProvider.get(), baseUrlInterceptorProvider.get());
  }

  public static NetworkModule_ProvideOkHttpClientFactory create(
      Provider<AuthInterceptor> authInterceptorProvider,
      Provider<BaseUrlInterceptor> baseUrlInterceptorProvider) {
    return new NetworkModule_ProvideOkHttpClientFactory(authInterceptorProvider, baseUrlInterceptorProvider);
  }

  public static OkHttpClient provideOkHttpClient(AuthInterceptor authInterceptor,
      BaseUrlInterceptor baseUrlInterceptor) {
    return Preconditions.checkNotNullFromProvides(NetworkModule.INSTANCE.provideOkHttpClient(authInterceptor, baseUrlInterceptor));
  }
}
