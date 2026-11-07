import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rekindle/core/read_aloud/kokoro_engine.dart';
import 'package:rekindle/core/read_aloud/voices.dart';

/// Seconds of audio in a 16-bit mono WAV file from [wav].
double seconds(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final rate = data.getUint32(24, Endian.little);
  return data.getUint32(40, Endian.little) / 2 / rate;
}

void main() {
  test('speech is written as a 16-bit mono WAV file', () {
    final bytes = wav(Float32List.fromList([0, 0.5, -0.5, 1, -1]), 24000);
    final data = ByteData.sublistView(bytes);
    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
    expect(data.getUint16(22, Endian.little), 1, reason: 'mono');
    expect(data.getUint32(24, Endian.little), 24000);
    expect(data.getUint16(34, Endian.little), 16, reason: '16-bit');
    expect(data.getUint32(40, Endian.little), 10, reason: 'five samples');
    expect(data.getInt16(46, Endian.little), 16384, reason: 'half volume');
    expect(data.getInt16(50, Endian.little), 32767, reason: 'clipped at full');
  });

  // Needs the model: KOKORO_MODEL_DIR is its unpacked folder, and SHERPA_LIB
  // the folder holding sherpa-onnx's libraries.
  final model = Platform.environment['KOKORO_MODEL_DIR'];
  final lib = Platform.environment['SHERPA_LIB'];
  test('Kokoro speaks queued sentences, in order', () async {
    final engine = await KokoroEngine.start(model!, voiceById('bf_emma'),
        libraryDir: lib);
    addTearDown(engine.dispose);
    // Asked for all at once, as the reader asks for the next ones ahead.
    final speech = await Future.wait([
      engine.speak('It is a truth universally acknowledged.'),
      engine.speak('Mr. Bennet replied that he had not.'),
      engine.speak('The Zxqvorth family lived at Netherfield.'),
    ]);
    final lengths = speech.map(seconds).toList();
    for (final bytes in speech) {
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
    }
    // Each is a spoken sentence: a couple of seconds, not silence or a click.
    for (final s in lengths) {
      expect(s, inInclusiveRange(1.2, 6));
    }
    // Every word is said, the unknown name included: an engine that skipped
    // words it had no pronunciation for came out much shorter.
    expect(lengths[2], greaterThan(2.2));
  }, skip: model == null || lib == null ? 'needs KOKORO_MODEL_DIR and SHERPA_LIB' : false,
      timeout: const Timeout(Duration(minutes: 2)));
}
