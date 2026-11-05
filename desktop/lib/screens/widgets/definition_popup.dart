import 'package:flutter/material.dart';

import '../../core/dictionary/wordnet_dictionary.dart';

/// A small card with a word's meanings. It sits over the page without taking focus
/// or moving anything, so the reader's place and flow are untouched.
class DefinitionPopup extends StatelessWidget {
  static const width = 340.0;
  static const maxHeight = 260.0;

  final String word;
  final List<DictionaryEntry> entries;
  final Color background;
  final Color foreground;

  const DefinitionPopup({
    super.key,
    required this.word,
    required this.entries,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    final muted = foreground.withValues(alpha: 0.7);
    return Material(
      color: background,
      elevation: 6,
      borderRadius: BorderRadius.circular(10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: width, maxHeight: maxHeight),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(14),
          child: DefaultTextStyle(
            style: TextStyle(color: foreground, fontSize: 14, height: 1.35),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (entries.isEmpty)
                  Text('No definition found for "$word".',
                      style: TextStyle(color: muted))
                else
                  for (final entry in entries) ...[
                    Text.rich(TextSpan(children: [
                      TextSpan(
                        text: entry.word,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      TextSpan(
                        text: '  ${entry.partOfSpeech}',
                        style: TextStyle(
                            color: muted, fontStyle: FontStyle.italic),
                      ),
                    ])),
                    const SizedBox(height: 4),
                    for (final (i, sense) in entry.senses.indexed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text.rich(TextSpan(children: [
                          TextSpan(text: '${i + 1}. ${sense.definition}'),
                          if (sense.example case final example?)
                            TextSpan(
                              text: '\n"$example"',
                              style: TextStyle(
                                  color: muted, fontStyle: FontStyle.italic),
                            ),
                        ])),
                      ),
                  ],
                Text('WordNet',
                    style: TextStyle(color: muted, fontSize: 11)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
