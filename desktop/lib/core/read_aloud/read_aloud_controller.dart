import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import 'kokoro_engine.dart';
import 'sentences.dart';
import 'voices.dart';

enum ReadAloudStatus { idle, starting, playing, paused }

/// Reads a chapter aloud a sentence at a time, and says which sentence it is
/// on so the reader can highlight it and keep it on screen.
///
/// The next two sentences are spoken ahead while one plays, so there is no
/// gap between them. At the end of a chapter [onChapterEnd] is called; the
/// reader opens the next chapter and hands it to [read].
class ReadAloudController extends ChangeNotifier {
  ReadAloudController({required this.onChapterEnd});

  /// Called when the last sentence of the chapter has been read.
  final VoidCallback onChapterEnd;

  ReadAloudStatus _status = ReadAloudStatus.idle;
  ReadAloudStatus get status => _status;
  bool get active => _status != ReadAloudStatus.idle;

  /// The sentence being read, in the chapter being read.
  int? _current;
  int? get current => _current;

  String? _error;
  String? get error => _error;

  KokoroEngine? _engine;
  MarkedChapter? _chapter;

  /// Bumped on every start and stop, so work for an earlier reading that
  /// finishes late is dropped rather than played.
  int _run = 0;
  final _ahead = <int, Future<Uint8List>>{};
  AudioSource? _source;
  SoundHandle? _handle;
  bool _disposed = false;

  static const _lookAhead = 2;

  /// Starts reading [chapter] from sentence [from], in [voice].
  Future<void> read(MarkedChapter chapter, int from,
      {required String modelDir, required KokoroVoice voice}) async {
    final run = await _reset();
    _chapter = chapter;
    _error = null;
    _set(ReadAloudStatus.starting);
    try {
      if (!SoLoud.instance.isInitialized) await SoLoud.instance.init();
      if (_engine?.voice.id != voice.id) {
        _engine?.dispose();
        _engine = null;
        _engine = await KokoroEngine.start(modelDir, voice);
      }
    } catch (e) {
      if (run == _run) _fail('$e');
      return;
    }
    if (run != _run) return;
    _set(ReadAloudStatus.playing);
    unawaited(_play(run, from));
  }

  void pause() {
    if (_status != ReadAloudStatus.playing) return;
    final handle = _handle;
    if (handle != null) SoLoud.instance.setPause(handle, true);
    _set(ReadAloudStatus.paused);
  }

  void resume() {
    if (_status != ReadAloudStatus.paused) return;
    final handle = _handle;
    if (handle != null) SoLoud.instance.setPause(handle, false);
    _set(ReadAloudStatus.playing);
  }

  Future<void> stop() async {
    await _reset();
    _current = null;
    _set(ReadAloudStatus.idle);
  }

  Future<int> _reset() async {
    final run = ++_run;
    _ahead.clear();
    final handle = _handle, source = _source;
    _handle = null;
    _source = null;
    if (handle != null && SoLoud.instance.getIsValidVoiceHandle(handle)) {
      await SoLoud.instance.stop(handle);
    }
    if (source != null) await SoLoud.instance.disposeSource(source);
    return run;
  }

  Future<Uint8List> _speech(int i) =>
      _ahead.remove(i) ?? _engine!.speak(_chapter!.sentences[i]);

  void _prefetch(int from) {
    final chapter = _chapter!;
    var queued = 0;
    for (var i = from; i < chapter.sentences.length && queued < _lookAhead; i++) {
      if (!chapter.speakable(i)) continue;
      _ahead.putIfAbsent(i, () => _engine!.speak(chapter.sentences[i]));
      queued++;
    }
  }

  Future<void> _play(int run, int i) async {
    final chapter = _chapter!;
    while (i < chapter.sentences.length && !chapter.speakable(i)) {
      i++;
    }
    if (i >= chapter.sentences.length) {
      onChapterEnd();
      return;
    }
    final Uint8List bytes;
    try {
      final speech = _speech(i);
      _prefetch(i + 1);
      bytes = await speech;
    } catch (e) {
      if (run == _run) _fail('$e');
      return;
    }
    if (run != _run) return;
    final source = await SoLoud.instance.loadMem('read-aloud-$run-$i.wav', bytes);
    if (run != _run) {
      await SoLoud.instance.disposeSource(source);
      return;
    }
    _source = source;
    _handle = SoLoud.instance
        .play(source, paused: _status == ReadAloudStatus.paused);
    _current = i;
    notifyListeners();
    await source.allInstancesFinished.first;
    if (run != _run) return;
    _source = null;
    _handle = null;
    await SoLoud.instance.disposeSource(source);
    if (run == _run) unawaited(_play(run, i + 1));
  }

  void _fail(String message) {
    _error = message;
    _current = null;
    _set(ReadAloudStatus.idle);
  }

  void _set(ReadAloudStatus status) {
    _status = status;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _reset();
    _engine?.dispose();
    super.dispose();
  }
}
