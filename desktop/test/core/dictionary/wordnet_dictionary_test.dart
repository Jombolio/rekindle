import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rekindle/core/dictionary/word_forms.dart';
import 'package:rekindle/core/dictionary/wordnet_dictionary.dart';
import 'package:rekindle/screens/widgets/definition_popup.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('WordForms', () {
    test('tidies a selection into a headword', () {
      expect(WordForms.normalize('  Dogs, '), 'dogs');
      expect(WordForms.normalize('“dog’s”'), 'dog');
      expect(WordForms.normalize('Ice\n cream.'), 'ice cream');
      expect(WordForms.normalize('well-known'), 'well-known');
    });

    test('a sentence or nothing at all is not a word', () {
      expect(WordForms.normalize('the quick brown fox jumps'), isNull);
      expect(WordForms.normalize(' ... '), isNull);
    });

    test('undoes inflections, keeping the word itself first', () {
      expect(WordForms.stems('running').first, 'running');
      expect(WordForms.stems('running'), isNot(contains('run')),
          reason: "doubled consonants aren't a rule");
      expect(WordForms.stems('making'), contains('make'));
      expect(WordForms.stems('walked'), contains('walk'));
      expect(WordForms.stems('cities'), contains('city'));
      expect(WordForms.stems('boxes'), contains('box'));
      expect(WordForms.stems('firemen'), contains('fireman'));
      expect(WordForms.stems('larger'), contains('large'));
    });

    test("a suffix can't be the whole word", () {
      expect(WordForms.stems('s'), ['s']);
    });
  });

  // Runs against the real database the app ships.
  group('WordNetDictionary', () {
    late Directory temp;
    late Database db;
    late WordNetDictionary dictionary;

    setUpAll(() async {
      sqfliteFfiInit();
      temp = await Directory.systemTemp.createTemp('wordnet');
      final file = File('${temp.path}/wordnet.db');
      file.writeAsBytesSync(
          gzip.decode(File('assets/dictionary/wordnet.db.gz').readAsBytesSync()));
      db = await databaseFactoryFfi.openDatabase(
        file.path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      dictionary = WordNetDictionary(db);
    });

    tearDownAll(() async {
      await db.close();
      await temp.delete(recursive: true);
    });

    Future<Set<String>> wordsFor(String selection) async =>
        (await dictionary.lookup(selection)).map((e) => e.word).toSet();

    test('finds a word in every part of speech, most common meaning first', () async {
      final entries = await dictionary.lookup('fast');
      expect(entries.map((e) => e.partOfSpeech),
          containsAll(['noun', 'verb', 'adjective', 'adverb']));
      expect(entries.first.senses.first.definition, isNotEmpty);
      expect(entries.every((e) => e.senses.length <= 3), isTrue);
    });

    test('finds regular and irregular inflections', () async {
      expect(await wordsFor('Cities,'), contains('city'));
      expect(await wordsFor('making'), contains('make'));
      expect(await wordsFor('mice'), contains('mouse'));
      expect(await wordsFor('ran'), contains('run'));
      expect(await wordsFor('running'), contains('run'),
          reason: 'via the exception table');
    });

    test('finds a phrase', () async {
      expect(await wordsFor('ice cream'), contains('ice cream'));
    });

    test('an unknown word or a sentence finds nothing', () async {
      expect(await dictionary.lookup('qwertyzxcv'), isEmpty);
      expect(await dictionary.lookup('the quick brown fox jumps over'), isEmpty);
    });

    test('examples are kept apart from definitions', () async {
      final entries = await dictionary.lookup('run');
      final sense = entries.first.senses.first;
      expect(sense.definition, isNot(contains('"')));
      expect(sense.example, isNotNull);
    });
  });

  testWidgets('the pop-up shows meanings, or says when there are none', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: DefinitionPopup(
          word: 'dog',
          entries: [
            DictionaryEntry('dog', 'noun', [DictionarySense('a pet', 'the dog barked')]),
          ],
          background: Colors.white,
          foreground: Colors.black,
        ),
      ),
    ));
    expect(find.textContaining('1. a pet', findRichText: true), findsOneWidget);
    expect(find.textContaining('the dog barked', findRichText: true), findsOneWidget);
    expect(find.text('WordNet'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: DefinitionPopup(
          word: 'zzz',
          entries: [],
          background: Colors.white,
          foreground: Colors.black,
        ),
      ),
    ));
    expect(find.textContaining('No definition found'), findsOneWidget);
  });
}
