import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/read_aloud/voices.dart';
import '../core/storage/prefs.dart';

/// The voice books are read aloud in.
final readAloudVoiceProvider =
    NotifierProvider<ReadAloudVoiceNotifier, KokoroVoice>(
        ReadAloudVoiceNotifier.new);

class ReadAloudVoiceNotifier extends Notifier<KokoroVoice> {
  @override
  KokoroVoice build() => voiceById(Prefs.instance.readAloudVoice);

  Future<void> select(KokoroVoice voice) async {
    state = voice;
    await Prefs.instance.setReadAloudVoice(voice.id);
  }
}

/// Whether Kokoro is on this computer, and how a download of it is going.
class VoicePack {
  /// The model's folder, once it is all there.
  final Directory? dir;

  /// Still finding out whether it is installed.
  final bool checking;

  /// How far a download is, 0 to 1, while one is running.
  final double? progress;
  final String? error;

  const VoicePack({this.dir, this.checking = false, this.progress, this.error});

  bool get installed => dir != null;
  bool get downloading => progress != null;
}

final voicePackProvider =
    NotifierProvider<VoicePackNotifier, VoicePack>(VoicePackNotifier.new);

class VoicePackNotifier extends Notifier<VoicePack> {
  CancelToken? _cancel;

  @override
  VoicePack build() {
    refresh();
    return const VoicePack(checking: true);
  }

  Future<void> refresh() async {
    final dir = await VoiceStore.installed();
    state = VoicePack(dir: dir);
  }

  Future<void> download() async {
    if (state.downloading) return;
    final cancel = _cancel = CancelToken();
    state = const VoicePack(progress: 0);
    try {
      await VoiceStore.download(
        cancel: cancel,
        onProgress: (received, total) {
          final size = total > 0 ? total : VoiceStore.approximateBytes;
          state = VoicePack(progress: (received / size).clamp(0.0, 1.0));
        },
      );
      state = VoicePack(dir: await VoiceStore.installed());
    } on DioException catch (e) {
      state = VoicePack(
          error: CancelToken.isCancel(e)
              ? null
              : 'The download failed: ${e.message ?? e.type.name}');
    } catch (e) {
      state = VoicePack(error: '$e');
    } finally {
      _cancel = null;
    }
  }

  void cancel() => _cancel?.cancel();

  Future<void> delete() async {
    await VoiceStore.delete();
    state = const VoicePack();
  }
}
