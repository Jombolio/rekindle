import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as so;

import 'voices.dart';

/// Kokoro, speaking a sentence at a time on its own isolate.
///
/// Speech takes over a second a sentence even on a fast machine, so it can't
/// run on the UI isolate. The model takes another second to load, so the
/// isolate is kept for as long as the reader is reading, and sentences are
/// queued to it: asking for the next two while one plays is what keeps the
/// voice from pausing between them.
class KokoroEngine {
  KokoroEngine._(this._isolate, this._requests, this.voice);

  final Isolate _isolate;
  final SendPort _requests;
  final KokoroVoice voice;

  /// Starts the engine for [voice] from the model in [modelDir].
  ///
  /// [libraryDir] is only for running outside the app, such as in a test: in
  /// the app the engine's libraries sit beside its executable.
  static Future<KokoroEngine> start(String modelDir, KokoroVoice voice,
      {String? libraryDir}) async {
    final ready = ReceivePort();
    final errors = ReceivePort();
    final isolate = await Isolate.spawn(
      _main,
      _Start(ready.sendPort, modelDir, voice.lexicon,
          (Platform.numberOfProcessors ~/ 2).clamp(2, 8), libraryDir),
      onError: errors.sendPort,
      debugName: 'kokoro',
    );
    final first = await Future.any([
      ready.first,
      errors.first.then((e) => 'The voice failed to start: $e'),
    ]);
    ready.close();
    errors.close();
    if (first is! SendPort) {
      isolate.kill(priority: Isolate.immediate);
      throw KokoroException('$first');
    }
    return KokoroEngine._(isolate, first, voice);
  }

  /// [text] as speech, a WAV file's bytes.
  Future<Uint8List> speak(String text, {double speed = 1}) async {
    final reply = ReceivePort();
    _requests.send(_Request(text, voice.speaker, speed, reply.sendPort));
    final result = await reply.first;
    reply.close();
    if (result is TransferableTypedData) {
      return result.materialize().asUint8List();
    }
    throw KokoroException('$result');
  }

  void dispose() {
    // Lets the isolate free the model before it goes.
    _requests.send(null);
    Timer(const Duration(seconds: 2),
        () => _isolate.kill(priority: Isolate.immediate));
  }
}

class KokoroException implements Exception {
  final String message;
  const KokoroException(this.message);
  @override
  String toString() => message;
}

class _Start {
  final SendPort ready;
  final String modelDir;
  final String lexicon;
  final int threads;
  final String? libraryDir;
  const _Start(
      this.ready, this.modelDir, this.lexicon, this.threads, this.libraryDir);
}

class _Request {
  final String text;
  final int speaker;
  final double speed;
  final SendPort reply;
  const _Request(this.text, this.speaker, this.speed, this.reply);
}

void _main(_Start start) {
  final so.OfflineTts tts;
  try {
    // In the app the libraries sit beside its executable, where Windows looks
    // before System32 — which has an older onnxruntime.dll of its own that the
    // engine can't use. From anywhere else, load the right one first by path,
    // so the engine's request for it by name finds it already loaded.
    final lib = start.libraryDir;
    if (lib != null && Platform.isWindows) {
      DynamicLibrary.open('$lib/onnxruntime.dll');
    }
    so.initBindings(lib);
    final dir = start.modelDir;
    tts = so.OfflineTts(so.OfflineTtsConfig(
      model: so.OfflineTtsModelConfig(
        kokoro: so.OfflineTtsKokoroModelConfig(
          model: '$dir/model.onnx',
          voices: '$dir/voices.bin',
          tokens: '$dir/tokens.txt',
          dataDir: '$dir/espeak-ng-data',
          lexicon: '$dir/${start.lexicon}',
        ),
        numThreads: start.threads,
      ),
    ));
  } catch (e) {
    start.ready.send('$e');
    return;
  }
  final requests = ReceivePort();
  start.ready.send(requests.sendPort);
  requests.listen((message) {
    if (message is! _Request) {
      tts.free();
      requests.close();
      return;
    }
    try {
      final audio = tts.generate(
          text: message.text, sid: message.speaker, speed: message.speed);
      message.reply.send(TransferableTypedData.fromList(
          [wav(audio.samples, audio.sampleRate)]));
    } catch (e) {
      message.reply.send('$e');
    }
  });
}

/// [samples] as a 16-bit mono WAV file.
Uint8List wav(Float32List samples, int sampleRate) {
  final data = samples.length * 2;
  final out = ByteData(44 + data);
  void ascii(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      out.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  out.setUint32(4, 36 + data, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  out.setUint32(16, 16, Endian.little);
  out.setUint16(20, 1, Endian.little); // PCM
  out.setUint16(22, 1, Endian.little); // mono
  out.setUint32(24, sampleRate, Endian.little);
  out.setUint32(28, sampleRate * 2, Endian.little);
  out.setUint16(32, 2, Endian.little);
  out.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  out.setUint32(40, data, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    final s = (samples[i].clamp(-1.0, 1.0) * 32767).round();
    out.setInt16(44 + i * 2, s, Endian.little);
  }
  return out.buffer.asUint8List();
}
