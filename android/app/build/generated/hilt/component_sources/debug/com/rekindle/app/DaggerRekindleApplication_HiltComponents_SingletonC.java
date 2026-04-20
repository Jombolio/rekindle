package com.rekindle.app;

import android.app.Activity;
import android.app.Service;
import android.content.Context;
import android.view.View;
import androidx.fragment.app.Fragment;
import androidx.hilt.work.HiltWorkerFactory;
import androidx.hilt.work.WorkerAssistedFactory;
import androidx.hilt.work.WorkerFactoryModule_ProvideFactoryFactory;
import androidx.lifecycle.SavedStateHandle;
import androidx.lifecycle.ViewModel;
import androidx.work.ListenableWorker;
import androidx.work.WorkerParameters;
import com.rekindle.app.core.connectivity.ConnectivityMonitor;
import com.rekindle.app.core.download.DownloadManager;
import com.rekindle.app.core.prefs.PrefsStore;
import com.rekindle.app.core.sync.SyncWorker;
import com.rekindle.app.core.sync.SyncWorker_AssistedFactory;
import com.rekindle.app.data.api.AuthInterceptor;
import com.rekindle.app.data.api.BaseUrlInterceptor;
import com.rekindle.app.data.api.RekindleApi;
import com.rekindle.app.data.db.AppDatabase;
import com.rekindle.app.data.db.DownloadDao;
import com.rekindle.app.data.db.ProgressQueueDao;
import com.rekindle.app.data.di.DatabaseModule_ProvideDatabaseFactory;
import com.rekindle.app.data.di.DatabaseModule_ProvideDownloadDaoFactory;
import com.rekindle.app.data.di.DatabaseModule_ProvideProgressQueueDaoFactory;
import com.rekindle.app.data.di.NetworkModule_ProvideOkHttpClientFactory;
import com.rekindle.app.data.di.NetworkModule_ProvideRekindleApiFactory;
import com.rekindle.app.data.di.NetworkModule_ProvideRetrofitFactory;
import com.rekindle.app.data.repository.AuthRepository;
import com.rekindle.app.data.repository.DownloadRepository;
import com.rekindle.app.data.repository.MediaRepository;
import com.rekindle.app.ui.viewmodel.ChapterIndexViewModel;
import com.rekindle.app.ui.viewmodel.ChapterIndexViewModel_HiltModules;
import com.rekindle.app.ui.viewmodel.EpubReaderViewModel;
import com.rekindle.app.ui.viewmodel.EpubReaderViewModel_HiltModules;
import com.rekindle.app.ui.viewmodel.LibraryViewModel;
import com.rekindle.app.ui.viewmodel.LibraryViewModel_HiltModules;
import com.rekindle.app.ui.viewmodel.LoginViewModel;
import com.rekindle.app.ui.viewmodel.LoginViewModel_HiltModules;
import com.rekindle.app.ui.viewmodel.MediaGridViewModel;
import com.rekindle.app.ui.viewmodel.MediaGridViewModel_HiltModules;
import com.rekindle.app.ui.viewmodel.ReaderViewModel;
import com.rekindle.app.ui.viewmodel.ReaderViewModel_HiltModules;
import com.rekindle.app.ui.viewmodel.SettingsViewModel;
import com.rekindle.app.ui.viewmodel.SettingsViewModel_HiltModules;
import dagger.hilt.android.ActivityRetainedLifecycle;
import dagger.hilt.android.ViewModelLifecycle;
import dagger.hilt.android.internal.builders.ActivityComponentBuilder;
import dagger.hilt.android.internal.builders.ActivityRetainedComponentBuilder;
import dagger.hilt.android.internal.builders.FragmentComponentBuilder;
import dagger.hilt.android.internal.builders.ServiceComponentBuilder;
import dagger.hilt.android.internal.builders.ViewComponentBuilder;
import dagger.hilt.android.internal.builders.ViewModelComponentBuilder;
import dagger.hilt.android.internal.builders.ViewWithFragmentComponentBuilder;
import dagger.hilt.android.internal.lifecycle.DefaultViewModelFactories;
import dagger.hilt.android.internal.lifecycle.DefaultViewModelFactories_InternalFactoryFactory_Factory;
import dagger.hilt.android.internal.managers.ActivityRetainedComponentManager_LifecycleModule_ProvideActivityRetainedLifecycleFactory;
import dagger.hilt.android.internal.managers.SavedStateHandleHolder;
import dagger.hilt.android.internal.modules.ApplicationContextModule;
import dagger.hilt.android.internal.modules.ApplicationContextModule_ProvideContextFactory;
import dagger.internal.DaggerGenerated;
import dagger.internal.DoubleCheck;
import dagger.internal.IdentifierNameString;
import dagger.internal.KeepFieldType;
import dagger.internal.LazyClassKeyMap;
import dagger.internal.MapBuilder;
import dagger.internal.Preconditions;
import dagger.internal.Provider;
import dagger.internal.SingleCheck;
import java.util.Collections;
import java.util.Map;
import java.util.Set;
import javax.annotation.processing.Generated;
import okhttp3.OkHttpClient;
import retrofit2.Retrofit;

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
public final class DaggerRekindleApplication_HiltComponents_SingletonC {
  private DaggerRekindleApplication_HiltComponents_SingletonC() {
  }

  public static Builder builder() {
    return new Builder();
  }

  public static final class Builder {
    private ApplicationContextModule applicationContextModule;

    private Builder() {
    }

    public Builder applicationContextModule(ApplicationContextModule applicationContextModule) {
      this.applicationContextModule = Preconditions.checkNotNull(applicationContextModule);
      return this;
    }

    public RekindleApplication_HiltComponents.SingletonC build() {
      Preconditions.checkBuilderRequirement(applicationContextModule, ApplicationContextModule.class);
      return new SingletonCImpl(applicationContextModule);
    }
  }

  private static final class ActivityRetainedCBuilder implements RekindleApplication_HiltComponents.ActivityRetainedC.Builder {
    private final SingletonCImpl singletonCImpl;

    private SavedStateHandleHolder savedStateHandleHolder;

    private ActivityRetainedCBuilder(SingletonCImpl singletonCImpl) {
      this.singletonCImpl = singletonCImpl;
    }

    @Override
    public ActivityRetainedCBuilder savedStateHandleHolder(
        SavedStateHandleHolder savedStateHandleHolder) {
      this.savedStateHandleHolder = Preconditions.checkNotNull(savedStateHandleHolder);
      return this;
    }

    @Override
    public RekindleApplication_HiltComponents.ActivityRetainedC build() {
      Preconditions.checkBuilderRequirement(savedStateHandleHolder, SavedStateHandleHolder.class);
      return new ActivityRetainedCImpl(singletonCImpl, savedStateHandleHolder);
    }
  }

  private static final class ActivityCBuilder implements RekindleApplication_HiltComponents.ActivityC.Builder {
    private final SingletonCImpl singletonCImpl;

    private final ActivityRetainedCImpl activityRetainedCImpl;

    private Activity activity;

    private ActivityCBuilder(SingletonCImpl singletonCImpl,
        ActivityRetainedCImpl activityRetainedCImpl) {
      this.singletonCImpl = singletonCImpl;
      this.activityRetainedCImpl = activityRetainedCImpl;
    }

    @Override
    public ActivityCBuilder activity(Activity activity) {
      this.activity = Preconditions.checkNotNull(activity);
      return this;
    }

    @Override
    public RekindleApplication_HiltComponents.ActivityC build() {
      Preconditions.checkBuilderRequirement(activity, Activity.class);
      return new ActivityCImpl(singletonCImpl, activityRetainedCImpl, activity);
    }
  }

  private static final class FragmentCBuilder implements RekindleApplication_HiltComponents.FragmentC.Builder {
    private final SingletonCImpl singletonCImpl;

    private final ActivityRetainedCImpl activityRetainedCImpl;

    private final ActivityCImpl activityCImpl;

    private Fragment fragment;

    private FragmentCBuilder(SingletonCImpl singletonCImpl,
        ActivityRetainedCImpl activityRetainedCImpl, ActivityCImpl activityCImpl) {
      this.singletonCImpl = singletonCImpl;
      this.activityRetainedCImpl = activityRetainedCImpl;
      this.activityCImpl = activityCImpl;
    }

    @Override
    public FragmentCBuilder fragment(Fragment fragment) {
      this.fragment = Preconditions.checkNotNull(fragment);
      return this;
    }

    @Override
    public RekindleApplication_HiltComponents.FragmentC build() {
      Preconditions.checkBuilderRequirement(fragment, Fragment.class);
      return new FragmentCImpl(singletonCImpl, activityRetainedCImpl, activityCImpl, fragment);
    }
  }

  private static final class ViewWithFragmentCBuilder implements RekindleApplication_HiltComponents.ViewWithFragmentC.Builder {
    private final SingletonCImpl singletonCImpl;

    private final ActivityRetainedCImpl activityRetainedCImpl;

    private final ActivityCImpl activityCImpl;

    private final FragmentCImpl fragmentCImpl;

    private View view;

    private ViewWithFragmentCBuilder(SingletonCImpl singletonCImpl,
        ActivityRetainedCImpl activityRetainedCImpl, ActivityCImpl activityCImpl,
        FragmentCImpl fragmentCImpl) {
      this.singletonCImpl = singletonCImpl;
      this.activityRetainedCImpl = activityRetainedCImpl;
      this.activityCImpl = activityCImpl;
      this.fragmentCImpl = fragmentCImpl;
    }

    @Override
    public ViewWithFragmentCBuilder view(View view) {
      this.view = Preconditions.checkNotNull(view);
      return this;
    }

    @Override
    public RekindleApplication_HiltComponents.ViewWithFragmentC build() {
      Preconditions.checkBuilderRequirement(view, View.class);
      return new ViewWithFragmentCImpl(singletonCImpl, activityRetainedCImpl, activityCImpl, fragmentCImpl, view);
    }
  }

  private static final class ViewCBuilder implements RekindleApplication_HiltComponents.ViewC.Builder {
    private final SingletonCImpl singletonCImpl;

    private final ActivityRetainedCImpl activityRetainedCImpl;

    private final ActivityCImpl activityCImpl;

    private View view;

    private ViewCBuilder(SingletonCImpl singletonCImpl, ActivityRetainedCImpl activityRetainedCImpl,
        ActivityCImpl activityCImpl) {
      this.singletonCImpl = singletonCImpl;
      this.activityRetainedCImpl = activityRetainedCImpl;
      this.activityCImpl = activityCImpl;
    }

    @Override
    public ViewCBuilder view(View view) {
      this.view = Preconditions.checkNotNull(view);
      return this;
    }

    @Override
    public RekindleApplication_HiltComponents.ViewC build() {
      Preconditions.checkBuilderRequirement(view, View.class);
      return new ViewCImpl(singletonCImpl, activityRetainedCImpl, activityCImpl, view);
    }
  }

  private static final class ViewModelCBuilder implements RekindleApplication_HiltComponents.ViewModelC.Builder {
    private final SingletonCImpl singletonCImpl;

    private final ActivityRetainedCImpl activityRetainedCImpl;

    private SavedStateHandle savedStateHandle;

    private ViewModelLifecycle viewModelLifecycle;

    private ViewModelCBuilder(SingletonCImpl singletonCImpl,
        ActivityRetainedCImpl activityRetainedCImpl) {
      this.singletonCImpl = singletonCImpl;
      this.activityRetainedCImpl = activityRetainedCImpl;
    }

    @Override
    public ViewModelCBuilder savedStateHandle(SavedStateHandle handle) {
      this.savedStateHandle = Preconditions.checkNotNull(handle);
      return this;
    }

    @Override
    public ViewModelCBuilder viewModelLifecycle(ViewModelLifecycle viewModelLifecycle) {
      this.viewModelLifecycle = Preconditions.checkNotNull(viewModelLifecycle);
      return this;
    }

    @Override
    public RekindleApplication_HiltComponents.ViewModelC build() {
      Preconditions.checkBuilderRequirement(savedStateHandle, SavedStateHandle.class);
      Preconditions.checkBuilderRequirement(viewModelLifecycle, ViewModelLifecycle.class);
      return new ViewModelCImpl(singletonCImpl, activityRetainedCImpl, savedStateHandle, viewModelLifecycle);
    }
  }

  private static final class ServiceCBuilder implements RekindleApplication_HiltComponents.ServiceC.Builder {
    private final SingletonCImpl singletonCImpl;

    private Service service;

    private ServiceCBuilder(SingletonCImpl singletonCImpl) {
      this.singletonCImpl = singletonCImpl;
    }

    @Override
    public ServiceCBuilder service(Service service) {
      this.service = Preconditions.checkNotNull(service);
      return this;
    }

    @Override
    public RekindleApplication_HiltComponents.ServiceC build() {
      Preconditions.checkBuilderRequirement(service, Service.class);
      return new ServiceCImpl(singletonCImpl, service);
    }
  }

  private static final class ViewWithFragmentCImpl extends RekindleApplication_HiltComponents.ViewWithFragmentC {
    private final SingletonCImpl singletonCImpl;

    private final ActivityRetainedCImpl activityRetainedCImpl;

    private final ActivityCImpl activityCImpl;

    private final FragmentCImpl fragmentCImpl;

    private final ViewWithFragmentCImpl viewWithFragmentCImpl = this;

    private ViewWithFragmentCImpl(SingletonCImpl singletonCImpl,
        ActivityRetainedCImpl activityRetainedCImpl, ActivityCImpl activityCImpl,
        FragmentCImpl fragmentCImpl, View viewParam) {
      this.singletonCImpl = singletonCImpl;
      this.activityRetainedCImpl = activityRetainedCImpl;
      this.activityCImpl = activityCImpl;
      this.fragmentCImpl = fragmentCImpl;


    }
  }

  private static final class FragmentCImpl extends RekindleApplication_HiltComponents.FragmentC {
    private final SingletonCImpl singletonCImpl;

    private final ActivityRetainedCImpl activityRetainedCImpl;

    private final ActivityCImpl activityCImpl;

    private final FragmentCImpl fragmentCImpl = this;

    private FragmentCImpl(SingletonCImpl singletonCImpl,
        ActivityRetainedCImpl activityRetainedCImpl, ActivityCImpl activityCImpl,
        Fragment fragmentParam) {
      this.singletonCImpl = singletonCImpl;
      this.activityRetainedCImpl = activityRetainedCImpl;
      this.activityCImpl = activityCImpl;


    }

    @Override
    public DefaultViewModelFactories.InternalFactoryFactory getHiltInternalFactoryFactory() {
      return activityCImpl.getHiltInternalFactoryFactory();
    }

    @Override
    public ViewWithFragmentComponentBuilder viewWithFragmentComponentBuilder() {
      return new ViewWithFragmentCBuilder(singletonCImpl, activityRetainedCImpl, activityCImpl, fragmentCImpl);
    }
  }

  private static final class ViewCImpl extends RekindleApplication_HiltComponents.ViewC {
    private final SingletonCImpl singletonCImpl;

    private final ActivityRetainedCImpl activityRetainedCImpl;

    private final ActivityCImpl activityCImpl;

    private final ViewCImpl viewCImpl = this;

    private ViewCImpl(SingletonCImpl singletonCImpl, ActivityRetainedCImpl activityRetainedCImpl,
        ActivityCImpl activityCImpl, View viewParam) {
      this.singletonCImpl = singletonCImpl;
      this.activityRetainedCImpl = activityRetainedCImpl;
      this.activityCImpl = activityCImpl;


    }
  }

  private static final class ActivityCImpl extends RekindleApplication_HiltComponents.ActivityC {
    private final SingletonCImpl singletonCImpl;

    private final ActivityRetainedCImpl activityRetainedCImpl;

    private final ActivityCImpl activityCImpl = this;

    private ActivityCImpl(SingletonCImpl singletonCImpl,
        ActivityRetainedCImpl activityRetainedCImpl, Activity activityParam) {
      this.singletonCImpl = singletonCImpl;
      this.activityRetainedCImpl = activityRetainedCImpl;


    }

    @Override
    public void injectMainActivity(MainActivity mainActivity) {
      injectMainActivity2(mainActivity);
    }

    @Override
    public DefaultViewModelFactories.InternalFactoryFactory getHiltInternalFactoryFactory() {
      return DefaultViewModelFactories_InternalFactoryFactory_Factory.newInstance(getViewModelKeys(), new ViewModelCBuilder(singletonCImpl, activityRetainedCImpl));
    }

    @Override
    public Map<Class<?>, Boolean> getViewModelKeys() {
      return LazyClassKeyMap.<Boolean>of(MapBuilder.<String, Boolean>newMapBuilder(7).put(LazyClassKeyProvider.com_rekindle_app_ui_viewmodel_ChapterIndexViewModel, ChapterIndexViewModel_HiltModules.KeyModule.provide()).put(LazyClassKeyProvider.com_rekindle_app_ui_viewmodel_EpubReaderViewModel, EpubReaderViewModel_HiltModules.KeyModule.provide()).put(LazyClassKeyProvider.com_rekindle_app_ui_viewmodel_LibraryViewModel, LibraryViewModel_HiltModules.KeyModule.provide()).put(LazyClassKeyProvider.com_rekindle_app_ui_viewmodel_LoginViewModel, LoginViewModel_HiltModules.KeyModule.provide()).put(LazyClassKeyProvider.com_rekindle_app_ui_viewmodel_MediaGridViewModel, MediaGridViewModel_HiltModules.KeyModule.provide()).put(LazyClassKeyProvider.com_rekindle_app_ui_viewmodel_ReaderViewModel, ReaderViewModel_HiltModules.KeyModule.provide()).put(LazyClassKeyProvider.com_rekindle_app_ui_viewmodel_SettingsViewModel, SettingsViewModel_HiltModules.KeyModule.provide()).build());
    }

    @Override
    public ViewModelComponentBuilder getViewModelComponentBuilder() {
      return new ViewModelCBuilder(singletonCImpl, activityRetainedCImpl);
    }

    @Override
    public FragmentComponentBuilder fragmentComponentBuilder() {
      return new FragmentCBuilder(singletonCImpl, activityRetainedCImpl, activityCImpl);
    }

    @Override
    public ViewComponentBuilder viewComponentBuilder() {
      return new ViewCBuilder(singletonCImpl, activityRetainedCImpl, activityCImpl);
    }

    private MainActivity injectMainActivity2(MainActivity instance) {
      MainActivity_MembersInjector.injectConnectivityMonitor(instance, singletonCImpl.connectivityMonitorProvider.get());
      return instance;
    }

    @IdentifierNameString
    private static final class LazyClassKeyProvider {
      static String com_rekindle_app_ui_viewmodel_MediaGridViewModel = "com.rekindle.app.ui.viewmodel.MediaGridViewModel";

      static String com_rekindle_app_ui_viewmodel_SettingsViewModel = "com.rekindle.app.ui.viewmodel.SettingsViewModel";

      static String com_rekindle_app_ui_viewmodel_LibraryViewModel = "com.rekindle.app.ui.viewmodel.LibraryViewModel";

      static String com_rekindle_app_ui_viewmodel_EpubReaderViewModel = "com.rekindle.app.ui.viewmodel.EpubReaderViewModel";

      static String com_rekindle_app_ui_viewmodel_ReaderViewModel = "com.rekindle.app.ui.viewmodel.ReaderViewModel";

      static String com_rekindle_app_ui_viewmodel_LoginViewModel = "com.rekindle.app.ui.viewmodel.LoginViewModel";

      static String com_rekindle_app_ui_viewmodel_ChapterIndexViewModel = "com.rekindle.app.ui.viewmodel.ChapterIndexViewModel";

      @KeepFieldType
      MediaGridViewModel com_rekindle_app_ui_viewmodel_MediaGridViewModel2;

      @KeepFieldType
      SettingsViewModel com_rekindle_app_ui_viewmodel_SettingsViewModel2;

      @KeepFieldType
      LibraryViewModel com_rekindle_app_ui_viewmodel_LibraryViewModel2;

      @KeepFieldType
      EpubReaderViewModel com_rekindle_app_ui_viewmodel_EpubReaderViewModel2;

      @KeepFieldType
      ReaderViewModel com_rekindle_app_ui_viewmodel_ReaderViewModel2;

      @KeepFieldType
      LoginViewModel com_rekindle_app_ui_viewmodel_LoginViewModel2;

      @KeepFieldType
      ChapterIndexViewModel com_rekindle_app_ui_viewmodel_ChapterIndexViewModel2;
    }
  }

  private static final class ViewModelCImpl extends RekindleApplication_HiltComponents.ViewModelC {
    private final SavedStateHandle savedStateHandle;

    private final SingletonCImpl singletonCImpl;

    private final ActivityRetainedCImpl activityRetainedCImpl;

    private final ViewModelCImpl viewModelCImpl = this;

    private Provider<ChapterIndexViewModel> chapterIndexViewModelProvider;

    private Provider<EpubReaderViewModel> epubReaderViewModelProvider;

    private Provider<LibraryViewModel> libraryViewModelProvider;

    private Provider<LoginViewModel> loginViewModelProvider;

    private Provider<MediaGridViewModel> mediaGridViewModelProvider;

    private Provider<ReaderViewModel> readerViewModelProvider;

    private Provider<SettingsViewModel> settingsViewModelProvider;

    private ViewModelCImpl(SingletonCImpl singletonCImpl,
        ActivityRetainedCImpl activityRetainedCImpl, SavedStateHandle savedStateHandleParam,
        ViewModelLifecycle viewModelLifecycleParam) {
      this.singletonCImpl = singletonCImpl;
      this.activityRetainedCImpl = activityRetainedCImpl;
      this.savedStateHandle = savedStateHandleParam;
      initialize(savedStateHandleParam, viewModelLifecycleParam);

    }

    @SuppressWarnings("unchecked")
    private void initialize(final SavedStateHandle savedStateHandleParam,
        final ViewModelLifecycle viewModelLifecycleParam) {
      this.chapterIndexViewModelProvider = new SwitchingProvider<>(singletonCImpl, activityRetainedCImpl, viewModelCImpl, 0);
      this.epubReaderViewModelProvider = new SwitchingProvider<>(singletonCImpl, activityRetainedCImpl, viewModelCImpl, 1);
      this.libraryViewModelProvider = new SwitchingProvider<>(singletonCImpl, activityRetainedCImpl, viewModelCImpl, 2);
      this.loginViewModelProvider = new SwitchingProvider<>(singletonCImpl, activityRetainedCImpl, viewModelCImpl, 3);
      this.mediaGridViewModelProvider = new SwitchingProvider<>(singletonCImpl, activityRetainedCImpl, viewModelCImpl, 4);
      this.readerViewModelProvider = new SwitchingProvider<>(singletonCImpl, activityRetainedCImpl, viewModelCImpl, 5);
      this.settingsViewModelProvider = new SwitchingProvider<>(singletonCImpl, activityRetainedCImpl, viewModelCImpl, 6);
    }

    @Override
    public Map<Class<?>, javax.inject.Provider<ViewModel>> getHiltViewModelMap() {
      return LazyClassKeyMap.<javax.inject.Provider<ViewModel>>of(MapBuilder.<String, javax.inject.Provider<ViewModel>>newMapBuilder(7).put(LazyClassKeyProvider.com_rekindle_app_ui_viewmodel_ChapterIndexViewModel, ((Provider) chapterIndexViewModelProvider)).put(LazyClassKeyProvider.com_rekindle_app_ui_viewmodel_EpubReaderViewModel, ((Provider) epubReaderViewModelProvider)).put(LazyClassKeyProvider.com_rekindle_app_ui_viewmodel_LibraryViewModel, ((Provider) libraryViewModelProvider)).put(LazyClassKeyProvider.com_rekindle_app_ui_viewmodel_LoginViewModel, ((Provider) loginViewModelProvider)).put(LazyClassKeyProvider.com_rekindle_app_ui_viewmodel_MediaGridViewModel, ((Provider) mediaGridViewModelProvider)).put(LazyClassKeyProvider.com_rekindle_app_ui_viewmodel_ReaderViewModel, ((Provider) readerViewModelProvider)).put(LazyClassKeyProvider.com_rekindle_app_ui_viewmodel_SettingsViewModel, ((Provider) settingsViewModelProvider)).build());
    }

    @Override
    public Map<Class<?>, Object> getHiltViewModelAssistedMap() {
      return Collections.<Class<?>, Object>emptyMap();
    }

    @IdentifierNameString
    private static final class LazyClassKeyProvider {
      static String com_rekindle_app_ui_viewmodel_LibraryViewModel = "com.rekindle.app.ui.viewmodel.LibraryViewModel";

      static String com_rekindle_app_ui_viewmodel_MediaGridViewModel = "com.rekindle.app.ui.viewmodel.MediaGridViewModel";

      static String com_rekindle_app_ui_viewmodel_ChapterIndexViewModel = "com.rekindle.app.ui.viewmodel.ChapterIndexViewModel";

      static String com_rekindle_app_ui_viewmodel_SettingsViewModel = "com.rekindle.app.ui.viewmodel.SettingsViewModel";

      static String com_rekindle_app_ui_viewmodel_LoginViewModel = "com.rekindle.app.ui.viewmodel.LoginViewModel";

      static String com_rekindle_app_ui_viewmodel_EpubReaderViewModel = "com.rekindle.app.ui.viewmodel.EpubReaderViewModel";

      static String com_rekindle_app_ui_viewmodel_ReaderViewModel = "com.rekindle.app.ui.viewmodel.ReaderViewModel";

      @KeepFieldType
      LibraryViewModel com_rekindle_app_ui_viewmodel_LibraryViewModel2;

      @KeepFieldType
      MediaGridViewModel com_rekindle_app_ui_viewmodel_MediaGridViewModel2;

      @KeepFieldType
      ChapterIndexViewModel com_rekindle_app_ui_viewmodel_ChapterIndexViewModel2;

      @KeepFieldType
      SettingsViewModel com_rekindle_app_ui_viewmodel_SettingsViewModel2;

      @KeepFieldType
      LoginViewModel com_rekindle_app_ui_viewmodel_LoginViewModel2;

      @KeepFieldType
      EpubReaderViewModel com_rekindle_app_ui_viewmodel_EpubReaderViewModel2;

      @KeepFieldType
      ReaderViewModel com_rekindle_app_ui_viewmodel_ReaderViewModel2;
    }

    private static final class SwitchingProvider<T> implements Provider<T> {
      private final SingletonCImpl singletonCImpl;

      private final ActivityRetainedCImpl activityRetainedCImpl;

      private final ViewModelCImpl viewModelCImpl;

      private final int id;

      SwitchingProvider(SingletonCImpl singletonCImpl, ActivityRetainedCImpl activityRetainedCImpl,
          ViewModelCImpl viewModelCImpl, int id) {
        this.singletonCImpl = singletonCImpl;
        this.activityRetainedCImpl = activityRetainedCImpl;
        this.viewModelCImpl = viewModelCImpl;
        this.id = id;
      }

      @SuppressWarnings("unchecked")
      @Override
      public T get() {
        switch (id) {
          case 0: // com.rekindle.app.ui.viewmodel.ChapterIndexViewModel 
          return (T) new ChapterIndexViewModel(viewModelCImpl.savedStateHandle, singletonCImpl.mediaRepositoryProvider.get(), singletonCImpl.downloadRepositoryProvider.get(), singletonCImpl.prefsStoreProvider.get());

          case 1: // com.rekindle.app.ui.viewmodel.EpubReaderViewModel 
          return (T) new EpubReaderViewModel(viewModelCImpl.savedStateHandle, singletonCImpl.downloadRepositoryProvider.get(), singletonCImpl.mediaRepositoryProvider.get(), singletonCImpl.prefsStoreProvider.get());

          case 2: // com.rekindle.app.ui.viewmodel.LibraryViewModel 
          return (T) new LibraryViewModel(singletonCImpl.provideRekindleApiProvider.get(), singletonCImpl.authRepositoryProvider.get(), singletonCImpl.prefsStoreProvider.get());

          case 3: // com.rekindle.app.ui.viewmodel.LoginViewModel 
          return (T) new LoginViewModel(singletonCImpl.authRepositoryProvider.get(), singletonCImpl.prefsStoreProvider.get());

          case 4: // com.rekindle.app.ui.viewmodel.MediaGridViewModel 
          return (T) new MediaGridViewModel(viewModelCImpl.savedStateHandle, singletonCImpl.mediaRepositoryProvider.get(), singletonCImpl.downloadRepositoryProvider.get(), singletonCImpl.prefsStoreProvider.get());

          case 5: // com.rekindle.app.ui.viewmodel.ReaderViewModel 
          return (T) new ReaderViewModel(viewModelCImpl.savedStateHandle, singletonCImpl.mediaRepositoryProvider.get(), singletonCImpl.downloadRepositoryProvider.get(), singletonCImpl.prefsStoreProvider.get());

          case 6: // com.rekindle.app.ui.viewmodel.SettingsViewModel 
          return (T) new SettingsViewModel(singletonCImpl.prefsStoreProvider.get(), ApplicationContextModule_ProvideContextFactory.provideContext(singletonCImpl.applicationContextModule));

          default: throw new AssertionError(id);
        }
      }
    }
  }

  private static final class ActivityRetainedCImpl extends RekindleApplication_HiltComponents.ActivityRetainedC {
    private final SingletonCImpl singletonCImpl;

    private final ActivityRetainedCImpl activityRetainedCImpl = this;

    private Provider<ActivityRetainedLifecycle> provideActivityRetainedLifecycleProvider;

    private ActivityRetainedCImpl(SingletonCImpl singletonCImpl,
        SavedStateHandleHolder savedStateHandleHolderParam) {
      this.singletonCImpl = singletonCImpl;

      initialize(savedStateHandleHolderParam);

    }

    @SuppressWarnings("unchecked")
    private void initialize(final SavedStateHandleHolder savedStateHandleHolderParam) {
      this.provideActivityRetainedLifecycleProvider = DoubleCheck.provider(new SwitchingProvider<ActivityRetainedLifecycle>(singletonCImpl, activityRetainedCImpl, 0));
    }

    @Override
    public ActivityComponentBuilder activityComponentBuilder() {
      return new ActivityCBuilder(singletonCImpl, activityRetainedCImpl);
    }

    @Override
    public ActivityRetainedLifecycle getActivityRetainedLifecycle() {
      return provideActivityRetainedLifecycleProvider.get();
    }

    private static final class SwitchingProvider<T> implements Provider<T> {
      private final SingletonCImpl singletonCImpl;

      private final ActivityRetainedCImpl activityRetainedCImpl;

      private final int id;

      SwitchingProvider(SingletonCImpl singletonCImpl, ActivityRetainedCImpl activityRetainedCImpl,
          int id) {
        this.singletonCImpl = singletonCImpl;
        this.activityRetainedCImpl = activityRetainedCImpl;
        this.id = id;
      }

      @SuppressWarnings("unchecked")
      @Override
      public T get() {
        switch (id) {
          case 0: // dagger.hilt.android.ActivityRetainedLifecycle 
          return (T) ActivityRetainedComponentManager_LifecycleModule_ProvideActivityRetainedLifecycleFactory.provideActivityRetainedLifecycle();

          default: throw new AssertionError(id);
        }
      }
    }
  }

  private static final class ServiceCImpl extends RekindleApplication_HiltComponents.ServiceC {
    private final SingletonCImpl singletonCImpl;

    private final ServiceCImpl serviceCImpl = this;

    private ServiceCImpl(SingletonCImpl singletonCImpl, Service serviceParam) {
      this.singletonCImpl = singletonCImpl;


    }
  }

  private static final class SingletonCImpl extends RekindleApplication_HiltComponents.SingletonC {
    private final ApplicationContextModule applicationContextModule;

    private final SingletonCImpl singletonCImpl = this;

    private Provider<PrefsStore> prefsStoreProvider;

    private Provider<OkHttpClient> provideOkHttpClientProvider;

    private Provider<Retrofit> provideRetrofitProvider;

    private Provider<RekindleApi> provideRekindleApiProvider;

    private Provider<AppDatabase> provideDatabaseProvider;

    private Provider<MediaRepository> mediaRepositoryProvider;

    private Provider<SyncWorker_AssistedFactory> syncWorker_AssistedFactoryProvider;

    private Provider<ConnectivityMonitor> connectivityMonitorProvider;

    private Provider<DownloadManager> downloadManagerProvider;

    private Provider<DownloadRepository> downloadRepositoryProvider;

    private Provider<AuthRepository> authRepositoryProvider;

    private SingletonCImpl(ApplicationContextModule applicationContextModuleParam) {
      this.applicationContextModule = applicationContextModuleParam;
      initialize(applicationContextModuleParam);

    }

    private AuthInterceptor authInterceptor() {
      return new AuthInterceptor(prefsStoreProvider.get());
    }

    private BaseUrlInterceptor baseUrlInterceptor() {
      return new BaseUrlInterceptor(prefsStoreProvider.get());
    }

    private ProgressQueueDao progressQueueDao() {
      return DatabaseModule_ProvideProgressQueueDaoFactory.provideProgressQueueDao(provideDatabaseProvider.get());
    }

    private Map<String, javax.inject.Provider<WorkerAssistedFactory<? extends ListenableWorker>>> mapOfStringAndProviderOfWorkerAssistedFactoryOf(
        ) {
      return Collections.<String, javax.inject.Provider<WorkerAssistedFactory<? extends ListenableWorker>>>singletonMap("com.rekindle.app.core.sync.SyncWorker", ((Provider) syncWorker_AssistedFactoryProvider));
    }

    private HiltWorkerFactory hiltWorkerFactory() {
      return WorkerFactoryModule_ProvideFactoryFactory.provideFactory(mapOfStringAndProviderOfWorkerAssistedFactoryOf());
    }

    private DownloadDao downloadDao() {
      return DatabaseModule_ProvideDownloadDaoFactory.provideDownloadDao(provideDatabaseProvider.get());
    }

    @SuppressWarnings("unchecked")
    private void initialize(final ApplicationContextModule applicationContextModuleParam) {
      this.prefsStoreProvider = DoubleCheck.provider(new SwitchingProvider<PrefsStore>(singletonCImpl, 5));
      this.provideOkHttpClientProvider = DoubleCheck.provider(new SwitchingProvider<OkHttpClient>(singletonCImpl, 4));
      this.provideRetrofitProvider = DoubleCheck.provider(new SwitchingProvider<Retrofit>(singletonCImpl, 3));
      this.provideRekindleApiProvider = DoubleCheck.provider(new SwitchingProvider<RekindleApi>(singletonCImpl, 2));
      this.provideDatabaseProvider = DoubleCheck.provider(new SwitchingProvider<AppDatabase>(singletonCImpl, 6));
      this.mediaRepositoryProvider = DoubleCheck.provider(new SwitchingProvider<MediaRepository>(singletonCImpl, 1));
      this.syncWorker_AssistedFactoryProvider = SingleCheck.provider(new SwitchingProvider<SyncWorker_AssistedFactory>(singletonCImpl, 0));
      this.connectivityMonitorProvider = DoubleCheck.provider(new SwitchingProvider<ConnectivityMonitor>(singletonCImpl, 7));
      this.downloadManagerProvider = DoubleCheck.provider(new SwitchingProvider<DownloadManager>(singletonCImpl, 9));
      this.downloadRepositoryProvider = DoubleCheck.provider(new SwitchingProvider<DownloadRepository>(singletonCImpl, 8));
      this.authRepositoryProvider = DoubleCheck.provider(new SwitchingProvider<AuthRepository>(singletonCImpl, 10));
    }

    @Override
    public void injectRekindleApplication(RekindleApplication rekindleApplication) {
      injectRekindleApplication2(rekindleApplication);
    }

    @Override
    public Set<Boolean> getDisableFragmentGetContextFix() {
      return Collections.<Boolean>emptySet();
    }

    @Override
    public ActivityRetainedComponentBuilder retainedComponentBuilder() {
      return new ActivityRetainedCBuilder(singletonCImpl);
    }

    @Override
    public ServiceComponentBuilder serviceComponentBuilder() {
      return new ServiceCBuilder(singletonCImpl);
    }

    private RekindleApplication injectRekindleApplication2(RekindleApplication instance) {
      RekindleApplication_MembersInjector.injectWorkerFactory(instance, hiltWorkerFactory());
      return instance;
    }

    private static final class SwitchingProvider<T> implements Provider<T> {
      private final SingletonCImpl singletonCImpl;

      private final int id;

      SwitchingProvider(SingletonCImpl singletonCImpl, int id) {
        this.singletonCImpl = singletonCImpl;
        this.id = id;
      }

      @SuppressWarnings("unchecked")
      @Override
      public T get() {
        switch (id) {
          case 0: // com.rekindle.app.core.sync.SyncWorker_AssistedFactory 
          return (T) new SyncWorker_AssistedFactory() {
            @Override
            public SyncWorker create(Context context, WorkerParameters params) {
              return new SyncWorker(context, params, singletonCImpl.mediaRepositoryProvider.get());
            }
          };

          case 1: // com.rekindle.app.data.repository.MediaRepository 
          return (T) new MediaRepository(singletonCImpl.provideRekindleApiProvider.get(), singletonCImpl.progressQueueDao());

          case 2: // com.rekindle.app.data.api.RekindleApi 
          return (T) NetworkModule_ProvideRekindleApiFactory.provideRekindleApi(singletonCImpl.provideRetrofitProvider.get());

          case 3: // retrofit2.Retrofit 
          return (T) NetworkModule_ProvideRetrofitFactory.provideRetrofit(singletonCImpl.provideOkHttpClientProvider.get());

          case 4: // okhttp3.OkHttpClient 
          return (T) NetworkModule_ProvideOkHttpClientFactory.provideOkHttpClient(singletonCImpl.authInterceptor(), singletonCImpl.baseUrlInterceptor());

          case 5: // com.rekindle.app.core.prefs.PrefsStore 
          return (T) new PrefsStore(ApplicationContextModule_ProvideContextFactory.provideContext(singletonCImpl.applicationContextModule));

          case 6: // com.rekindle.app.data.db.AppDatabase 
          return (T) DatabaseModule_ProvideDatabaseFactory.provideDatabase(ApplicationContextModule_ProvideContextFactory.provideContext(singletonCImpl.applicationContextModule));

          case 7: // com.rekindle.app.core.connectivity.ConnectivityMonitor 
          return (T) new ConnectivityMonitor(ApplicationContextModule_ProvideContextFactory.provideContext(singletonCImpl.applicationContextModule));

          case 8: // com.rekindle.app.data.repository.DownloadRepository 
          return (T) new DownloadRepository(singletonCImpl.downloadManagerProvider.get(), singletonCImpl.prefsStoreProvider.get());

          case 9: // com.rekindle.app.core.download.DownloadManager 
          return (T) new DownloadManager(ApplicationContextModule_ProvideContextFactory.provideContext(singletonCImpl.applicationContextModule), singletonCImpl.provideOkHttpClientProvider.get(), singletonCImpl.downloadDao());

          case 10: // com.rekindle.app.data.repository.AuthRepository 
          return (T) new AuthRepository(singletonCImpl.provideRekindleApiProvider.get(), singletonCImpl.prefsStoreProvider.get());

          default: throw new AssertionError(id);
        }
      }
    }
  }
}
