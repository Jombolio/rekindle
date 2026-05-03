import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'providers/auth_provider.dart';
import 'providers/connectivity_provider.dart';
import 'providers/reader_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/sources_provider.dart';
import 'screens/add_source_screen.dart';
import 'screens/admin_panel_screen.dart';
import 'screens/chapter_index_screen.dart';
import 'screens/epub_reader_screen.dart';
import 'screens/library_screen.dart';
import 'screens/media_grid_screen.dart';
import 'screens/reader_screen.dart';
import 'screens/settings_screen.dart';

final _routerProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = ValueNotifier<int>(0);
  ref.listen(authProvider, (_, __) => refreshNotifier.value++);
  ref.listen(sourcesProvider, (_, __) => refreshNotifier.value++);
  ref.onDispose(refreshNotifier.dispose);

  return GoRouter(
    refreshListenable: refreshNotifier,
    initialLocation: '/',
    redirect: (context, state) {
      final sources = ref.read(sourcesProvider);
      final activeId = ref.read(activeSourceIdProvider);
      final loc = state.matchedLocation;

      if (sources.isEmpty && loc != '/source/add') return '/source/add';

      // If the active (or only) source has lost its token (e.g. server restarted
      // and invalidated the JWT), bounce back to the library screen where the
      // per-source sign-in prompt will be shown.
      final activeSource = activeId != null
          ? sources.where((s) => s.id == activeId).firstOrNull
          : sources.firstOrNull;
      final isLoggedOut = activeSource != null && activeSource.token == null;
      const protectedPrefixes = ['/libraries/', '/series/', '/reader/', '/epub/', '/admin/'];
      if (isLoggedOut && protectedPrefixes.any((p) => loc.startsWith(p))) {
        return '/libraries';
      }

      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (_, __) => '/libraries'),
      GoRoute(
        path: '/source/add',
        builder: (_, __) => const AddSourceScreen(),
      ),
      GoRoute(
        path: '/libraries',
        builder: (_, __) => const LibraryScreen(),
      ),
      GoRoute(
        path: '/libraries/:id',
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return MediaGridScreen(
            libraryId: state.pathParameters['id']!,
            libraryName: extra?['name'] as String?,
            libraryType: extra?['type'] as String?,
          );
        },
      ),
      GoRoute(
        path: '/reader/:id',
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return ReaderScreen(
            mediaId: state.pathParameters['id']!,
            libraryType: extra?['libraryType'] as String?,
            initialPage: extra?['initialPage'] as int?,
          );
        },
      ),
      GoRoute(
        path: '/admin/:sourceId',
        builder: (_, state) =>
            AdminPanelScreen(sourceId: state.pathParameters['sourceId']!),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, __) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/series/:id',
        builder: (_, state) {
          final extra = state.extra as Map<String, String?>?;
          return ChapterIndexScreen(
            folderId: state.pathParameters['id']!,
            folderTitle: extra?['title'] ?? 'Series',
            libraryType: extra?['libraryType'],
          );
        },
      ),
      GoRoute(
        path: '/epub/:id',
        builder: (_, state) => EpubReaderScreen(
          mediaId: state.pathParameters['id']!,
          title: state.extra as String? ?? '',
        ),
      ),
    ],
  );
});

class RekindleApp extends ConsumerWidget {
  const RekindleApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(_routerProvider);
    final settings = ref.watch(settingsProvider);

    ref.listen(isOnlineProvider, (prev, isOnline) {
      if (isOnline && prev == false) {
        syncPendingProgress(ref);
      }
    });

    return MaterialApp.router(
      title: 'Rekindle',
      theme: _lightTheme(),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: settings.themeMode,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }

  static ThemeData _lightTheme() {
    const background = Color(0xFFF5F2ED);
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF6750A4),
        brightness: Brightness.light,
        surface: background,
        surfaceContainerLowest: background,
        surfaceContainerLow: Color(0xFFEFEBE5),
        surfaceContainer: Color(0xFFE9E5DF),
      ),
      scaffoldBackgroundColor: background,
      useMaterial3: true,
    );
  }
}
