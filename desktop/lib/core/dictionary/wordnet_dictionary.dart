import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'word_forms.dart';

class DictionarySense {
  final String definition;
  final String? example;
  const DictionarySense(this.definition, this.example);
}

/// One headword as one part of speech, with its most common meanings first.
class DictionaryEntry {
  final String word;
  final String partOfSpeech;
  final List<DictionarySense> senses;
  const DictionaryEntry(this.word, this.partOfSpeech, this.senses);
}

/// The built-in English dictionary, from WordNet. See tools/build_wordnet.py.
class WordNetDictionary {
  /// Bump with the database, so an app update replaces the unpacked copy.
  static const _version = 1;
  static const _maxWordsShown = 2;
  static const _maxSensesPerEntry = 3;
  static const _partsOfSpeech = {
    'n': 'noun',
    'v': 'verb',
    'a': 'adjective',
    'r': 'adverb',
  };

  final Database _db;
  WordNetDictionary(this._db);

  static WordNetDictionary? _instance;

  /// Opens the dictionary, unpacking it on first use. Unpacking only costs anything
  /// once, and only if the reader ever looks a word up.
  static Future<WordNetDictionary> open() async {
    final existing = _instance;
    if (existing != null) return existing;

    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, 'wordnet-$_version.db'));
    if (!file.existsSync()) {
      final packed = await rootBundle.load('assets/dictionary/wordnet.db.gz');
      final bytes = packed.buffer.asUint8List(packed.offsetInBytes, packed.lengthInBytes);
      final raw = await Isolate.run(() => gzip.decode(bytes));
      // Moved into place once complete, so a crash can't leave half a database.
      final temp = File('${file.path}.tmp');
      await temp.parent.create(recursive: true);
      await temp.writeAsBytes(raw, flush: true);
      await temp.rename(file.path);
    }

    final db = await databaseFactory.openDatabase(
      file.path,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    return _instance = WordNetDictionary(db);
  }

  /// Entries for a selection, or an empty list if it isn't in the dictionary.
  Future<List<DictionaryEntry>> lookup(String selection) async {
    final word = WordForms.normalize(selection);
    if (word == null) return const [];

    final candidates = <String>[word];
    final irregular = await _db.query(
      'exceptions',
      columns: ['lemma'],
      where: 'form = ?',
      whereArgs: [word],
    );
    candidates.addAll(irregular.map((r) => r['lemma'] as String));
    candidates.addAll(WordForms.stems(word));

    final entries = <DictionaryEntry>[];
    final seen = <String>{};
    for (final candidate in candidates) {
      if (!seen.add(candidate)) continue;
      final found = await _entriesFor(candidate);
      if (found.isEmpty) continue;
      entries.addAll(found);
      if (seen.length > 1 && entries.isNotEmpty) {
        final words = entries.map((e) => e.word).toSet();
        if (words.length >= _maxWordsShown) break;
      }
    }
    return entries;
  }

  Future<List<DictionaryEntry>> _entriesFor(String word) async {
    final rows = await _db.rawQuery(
      'SELECT s.pos, y.definition, y.example FROM senses s '
      'JOIN synsets y ON y.id = s.synset '
      'WHERE s.word = ? ORDER BY s.sense',
      [word],
    );
    final byPos = <String, List<DictionarySense>>{};
    for (final row in rows) {
      final senses = byPos.putIfAbsent(row['pos'] as String, () => []);
      if (senses.length < _maxSensesPerEntry) {
        senses.add(DictionarySense(
          row['definition'] as String,
          row['example'] as String?,
        ));
      }
    }
    return [
      for (final pos in _partsOfSpeech.keys)
        if (byPos[pos] case final senses?)
          DictionaryEntry(word, _partsOfSpeech[pos]!, senses),
    ];
  }
}
