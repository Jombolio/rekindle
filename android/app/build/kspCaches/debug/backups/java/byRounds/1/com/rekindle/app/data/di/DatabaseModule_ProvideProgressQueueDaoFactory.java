package com.rekindle.app.data.di;

import com.rekindle.app.data.db.AppDatabase;
import com.rekindle.app.data.db.ProgressQueueDao;
import dagger.internal.DaggerGenerated;
import dagger.internal.Factory;
import dagger.internal.Preconditions;
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
public final class DatabaseModule_ProvideProgressQueueDaoFactory implements Factory<ProgressQueueDao> {
  private final Provider<AppDatabase> dbProvider;

  public DatabaseModule_ProvideProgressQueueDaoFactory(Provider<AppDatabase> dbProvider) {
    this.dbProvider = dbProvider;
  }

  @Override
  public ProgressQueueDao get() {
    return provideProgressQueueDao(dbProvider.get());
  }

  public static DatabaseModule_ProvideProgressQueueDaoFactory create(
      Provider<AppDatabase> dbProvider) {
    return new DatabaseModule_ProvideProgressQueueDaoFactory(dbProvider);
  }

  public static ProgressQueueDao provideProgressQueueDao(AppDatabase db) {
    return Preconditions.checkNotNullFromProvides(DatabaseModule.INSTANCE.provideProgressQueueDao(db));
  }
}
