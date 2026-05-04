import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/server_source.dart';
import '../core/storage/prefs.dart';

class SourcesNotifier extends Notifier<List<ServerSource>> {
  @override
  List<ServerSource> build() => Prefs.instance.sources;

  Future<void> add(ServerSource source) async {
    state = [...state, source];
    await Prefs.instance.setSources(state);
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
