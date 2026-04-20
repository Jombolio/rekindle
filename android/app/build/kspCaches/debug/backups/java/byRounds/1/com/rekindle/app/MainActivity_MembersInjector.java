package com.rekindle.app;

import com.rekindle.app.core.connectivity.ConnectivityMonitor;
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
public final class MainActivity_MembersInjector implements MembersInjector<MainActivity> {
  private final Provider<ConnectivityMonitor> connectivityMonitorProvider;

  public MainActivity_MembersInjector(Provider<ConnectivityMonitor> connectivityMonitorProvider) {
    this.connectivityMonitorProvider = connectivityMonitorProvider;
  }

  public static MembersInjector<MainActivity> create(
      Provider<ConnectivityMonitor> connectivityMonitorProvider) {
    return new MainActivity_MembersInjector(connectivityMonitorProvider);
  }

  @Override
  public void injectMembers(MainActivity instance) {
    injectConnectivityMonitor(instance, connectivityMonitorProvider.get());
  }

  @InjectedFieldSignature("com.rekindle.app.MainActivity.connectivityMonitor")
  public static void injectConnectivityMonitor(MainActivity instance,
      ConnectivityMonitor connectivityMonitor) {
    instance.connectivityMonitor = connectivityMonitor;
  }
}
