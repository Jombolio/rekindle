package com.rekindle.app.data.di

import com.rekindle.app.core.prefs.PrefsStore
import com.rekindle.app.data.api.AuthInterceptor
import com.rekindle.app.data.api.BaseUrlInterceptor
import com.rekindle.app.data.api.RekindleApi
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object NetworkModule {

    @Provides
    @Singleton
    fun provideOkHttpClient(
        authInterceptor: AuthInterceptor,
        baseUrlInterceptor: BaseUrlInterceptor,
    ): OkHttpClient =
        OkHttpClient.Builder()
            .addInterceptor(baseUrlInterceptor)
            .addInterceptor(authInterceptor)
            .addInterceptor(HttpLoggingInterceptor().apply {
                level = HttpLoggingInterceptor.Level.BASIC
            })
            .build()

    @Provides
    @Singleton
    fun provideRetrofit(okHttpClient: OkHttpClient): Retrofit =
        Retrofit.Builder()
            // Placeholder — BaseUrlInterceptor rewrites the actual host at request time
            .baseUrl("http://localhost/")
            .client(okHttpClient)
            .addConverterFactory(GsonConverterFactory.create())
            .build()

    @Provides
    @Singleton
    fun provideRekindleApi(retrofit: Retrofit): RekindleApi =
        retrofit.create(RekindleApi::class.java)
}
