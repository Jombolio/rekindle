import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_client.dart';
import '../core/api/auth_api.dart';
import '../core/models/server_source.dart';
import '../core/storage/prefs.dart';
import 'sources_provider.dart';

// ---------------------------------------------------------------------------
// Active source — set when navigating into library/media/reader screens
// ---------------------------------------------------------------------------

final activeSourceIdProvider = StateProvider<String?>((ref) => null);

final apiClientProvider = Provider<ApiClient>((ref) {
  final sources = ref.watch(sourcesProvider);
  final activeId = ref.watch(activeSourceIdProvider);

  ServerSource? source;
  if (activeId != null) {
    source = sources.where((s) => s.id == activeId).firstOrNull;
  }
  source ??= sources.where((s) => s.token != null).firstOrNull;
  source ??= sources.firstOrNull;

  if (source == null) return ApiClient(baseUrl: '', token: null);
  return ApiClient(baseUrl: source.baseUrl, token: source.token);
});

// ---------------------------------------------------------------------------
// Per-source auth state — used by the library screen per source section
// ---------------------------------------------------------------------------

final sourceAuthProvider =
    FutureProvider.family<AuthState, String>((ref, sourceId) async {
  final sources = ref.watch(sourcesProvider);
  final source = sources.where((s) => s.id == sourceId).firstOrNull;
  if (source == null || source.token == null) return const AuthUnauthenticated();

  // Cache is written at login time (add_source_screen) so it is always
  // available after process death without a live network call.
  final cached = Prefs.instance.cachedAuth(sourceId);
  if (cached != null) {
    return AuthAuthenticated(
        username: cached.username, permissionLevel: cached.permissionLevel);
  }

  // No cache yet — first launch after a data-clear or migration; ask the server.
  try {
    final client = ApiClient(baseUrl: source.baseUrl, token: source.token);
    final data = await AuthApi(client).me();
    final username = data['username'] as String;
    final permLevel = data['permissionLevel'] as int? ?? 2;
    await Prefs.instance.setCachedAuth(sourceId, username, permLevel);
    final freshToken = data['token'] as String?;
    if (freshToken != null && freshToken != source.token) {
      await ref.read(sourcesProvider.notifier).setToken(sourceId, freshToken);
    }
    return AuthAuthenticated(username: username, permissionLevel: permLevel);
  } on DioException catch (e) {
    if (e.response?.statusCode == 401) {
      await Prefs.instance.clearCachedAuth(sourceId);
      return const AuthUnauthenticated();
    }
    return const AuthUnauthenticated();
  } catch (_) {
    return const AuthUnauthenticated();
  }
});

// ---------------------------------------------------------------------------
// Auth state
// ---------------------------------------------------------------------------

sealed class AuthState {
  const AuthState();
}

class AuthAuthenticated extends AuthState {
  final String username;
  final int permissionLevel;

  const AuthAuthenticated({
    required this.username,
    required this.permissionLevel,
  });

  bool get canRead => permissionLevel >= 1;
  bool get canDownload => permissionLevel >= 2;
  bool get canManageMedia => permissionLevel >= 3;
  bool get isAdmin => permissionLevel >= 4;
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

// ---------------------------------------------------------------------------
// Auth notifier — tracks auth for the active/primary source.
// Used by reader, media grid etc. that operate within a single source context.
// ---------------------------------------------------------------------------

class AuthNotifier extends AsyncNotifier<AuthState> {
  @override
  Future<AuthState> build() async {
    final sources = ref.watch(sourcesProvider);
    final activeId = ref.watch(activeSourceIdProvider);

    ServerSource? source;
    if (activeId != null) {
      source = sources.where((s) => s.id == activeId).firstOrNull;
    }
    source ??= sources.where((s) => s.token != null).firstOrNull;

    if (source == null || source.token == null) return const AuthUnauthenticated();

    final cached = Prefs.instance.cachedAuth(source.id);
    if (cached != null) {
      return AuthAuthenticated(
          username: cached.username, permissionLevel: cached.permissionLevel);
    }

    try {
      final client = ApiClient(baseUrl: source.baseUrl, token: source.token);
      final data = await AuthApi(client).me();
      return AuthAuthenticated(
        username: data['username'] as String,
        permissionLevel: data['permissionLevel'] as int? ?? 2,
      );
    } catch (_) {
      return const AuthUnauthenticated();
    }
  }

  Future<void> logout() async {
    final sources = ref.read(sourcesProvider);
    final activeId = ref.read(activeSourceIdProvider);
    final source = (activeId != null
            ? sources.where((s) => s.id == activeId).firstOrNull
            : null) ??
        sources.firstOrNull;
    if (source != null) {
      await Prefs.instance.clearCachedAuth(source.id);
      await ref.read(sourcesProvider.notifier).clearToken(source.id);
    }
    state = const AsyncData(AuthUnauthenticated());
  }

  static String errorMessage(Object error) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      if (status == 401) return 'Invalid credentials or incorrect setup token.';
      if (status == 409) return 'An admin account already exists. Please log in.';
      if (status == 400) {
        final msg = error.response?.data?['error'];
        if (msg is String) return msg;
      }
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        return 'Could not reach the server. Check the URL and try again.';
      }
    }
    return 'An unexpected error occurred.';
  }
}

final authProvider = AsyncNotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
