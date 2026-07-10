import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/server_source.dart';
import '../core/storage/prefs.dart';

class SourcesNotifier extends Notifier<List<ServerSource>> {
  @override
  List<ServerSource> build() => Prefs.instance.sources;

  /// Adds [source], or — if a source with the same base URL already exists
  /// (e.g. re-signing in after the token was lost) — updates that one in place
  /// instead of creating a duplicate. Returns the id of the effective source.
  Future<String> add(ServerSource source) async {
    String norm(String u) => u.trim().replaceAll(RegExp(r'/+$'), '');
    final idx = state.indexWhere((s) => norm(s.baseUrl) == norm(source.baseUrl));
    if (idx >= 0) {
      final existing = state[idx];
      state = [
        for (var i = 0; i < state.length; i++)
          if (i == idx) existing.copyWith(token: source.token) else state[i],
      ];
      await Prefs.instance.setSources(state);
      return existing.id;
    }
    state = [...state, source];
    await Prefs.instance.setSources(state);
    return source.id;
  }

  Future<void> remove(String id) async {
    state = [for (final s in state) if (s.id != id) s];
    await Prefs.instance.setSources(state);
    await Prefs.instance.clearCachedAuth(id);
  }

  Future<void> updateName(String id, String name) async {
    state = [for (final s in state) if (s.id == id) s.copyWith(name: name) else s];
    await Prefs.instance.setSources(state);
  }

  Future<void> setToken(String id, String token) async {
    state = [for (final s in state) if (s.id == id) s.copyWith(token: token) else s];
    await Prefs.instance.setSources(state);
  }

  Future<void> clearToken(String id) async {
    state = [
      for (final s in state)
        if (s.id == id) s.copyWith(clearToken: true) else s
    ];
    await Prefs.instance.setSources(state);
    await Prefs.instance.clearCachedAuth(id);
  }
}

final sourcesProvider = NotifierProvider<SourcesNotifier, List<ServerSource>>(
  SourcesNotifier.new,
);
