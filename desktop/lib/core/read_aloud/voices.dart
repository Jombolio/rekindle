import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// One of Kokoro's voices.
class KokoroVoice {
  /// Kokoro's own name for it, which is what is saved.
  final String id;
  final String label;

  /// Its number in the voice table that ships with the model.
  final int speaker;

  /// The pronunciation list for its accent. Words not in it go to espeak-ng.
  final String lexicon;

  const KokoroVoice(this.id, this.label, this.speaker, this.lexicon);
}

/// The voices offered. All are in the one model download; the numbers are the
/// speaker table of Kokoro v1.0 as sherpa-onnx packages it.
const kokoroVoices = [
  KokoroVoice('af_heart', 'Heart · American, female', 3, 'lexicon-us-en.txt'),
  KokoroVoice('bf_emma', 'Emma · British, female', 21, 'lexicon-gb-en.txt'),
  KokoroVoice('bm_george', 'George · British, male', 26, 'lexicon-gb-en.txt'),
];

KokoroVoice voiceById(String? id) =>
    kokoroVoices.firstWhere((v) => v.id == id, orElse: () => kokoroVoices[0]);

/// Where Kokoro is kept on this computer, and how it gets there.
///
/// It is downloaded once, on request, rather than shipped: the full-precision
/// model is about 333 MB. That one is used rather than the 126 MB int8 build
/// because int8 was 2.5–4 times slower on desktop CPUs, barely keeping pace
/// with speech.
class VoiceStore {
  static const pack = 'kokoro-multi-lang-v1_0';
  static const url = 'https://github.com/k2-fsa/sherpa-onnx/releases/download/'
      'tts-models/kokoro-multi-lang-v1_0.tar.bz2';
  static const approximateBytes = 333 * 1024 * 1024;

  /// The files a complete download has.
  static const _required = [
    'model.onnx',
    'voices.bin',
    'tokens.txt',
    'lexicon-us-en.txt',
    'lexicon-gb-en.txt',
    'espeak-ng-data',
  ];

  static Future<Directory> _root() async => Directory(
      p.join((await getApplicationSupportDirectory()).path, 'voices'));

  /// The model's folder, if it is all there.
  static Future<Directory?> installed() async {
    final dir = Directory(p.join((await _root()).path, pack));
    if (!await dir.exists()) return null;
    for (final name in _required) {
      final path = p.join(dir.path, name);
      if (!await File(path).exists() && !await Directory(path).exists()) {
        return null;
      }
    }
    return dir;
  }

  /// Downloads and unpacks the model. Unpacking goes to a temporary folder,
  /// moved into place only once it is complete, so a cancelled or failed
  /// download never leaves a half-installed voice behind.
  static Future<void> download({
    void Function(int received, int total)? onProgress,
    CancelToken? cancel,
  }) async {
    final root = await _root();
    await root.create(recursive: true);
    final archive = File(p.join(root.path, '$pack.tar.bz2.part'));
    final unpacking = Directory(p.join(root.path, '.unpacking'));
    try {
      await Dio().download(url, archive.path,
          onReceiveProgress: onProgress, cancelToken: cancel);
      if (await unpacking.exists()) await unpacking.delete(recursive: true);
      await unpacking.create();
      // tar ships with Windows 10 and later, and with every Linux.
      final result = await Process.run(
          'tar', ['-xjf', archive.path, '-C', unpacking.path]);
      if (result.exitCode != 0) {
        throw VoiceDownloadException(
            'Unpacking failed: ${(result.stderr as String).trim()}');
      }
      final target = Directory(p.join(root.path, pack));
      if (await target.exists()) await target.delete(recursive: true);
      await Directory(p.join(unpacking.path, pack)).rename(target.path);
      if (await installed() == null) {
        throw const VoiceDownloadException('The download was incomplete.');
      }
    } finally {
      if (await archive.exists()) await archive.delete();
      if (await unpacking.exists()) await unpacking.delete(recursive: true);
    }
  }

  static Future<void> delete() async {
    final dir = Directory(p.join((await _root()).path, pack));
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}

class VoiceDownloadException implements Exception {
  final String message;
  const VoiceDownloadException(this.message);
  @override
  String toString() => message;
}
