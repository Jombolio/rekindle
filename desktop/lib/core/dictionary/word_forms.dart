/// Works out which dictionary headwords a selection might be, so "running",
/// "mice" and "Dogs," all find their entries. Follows WordNet's own rules for
/// undoing inflections; irregular forms come from its exception table.
///
/// Android has the same rules in `WordForms.kt`. Keep the two in step.
class WordForms {
  static const maxWords = 4;
  static const _maxLength = 60;

  /// (suffix, replacement), tried in this order.
  static const _rules = <(String, String)>[
    // Nouns
    ('s', ''), ('ses', 's'), ('xes', 'x'), ('zes', 'z'), ('ches', 'ch'),
    ('shes', 'sh'), ('men', 'man'), ('ies', 'y'),
    // Verbs
    ('es', 'e'), ('es', ''), ('ed', 'e'), ('ed', ''), ('ing', 'e'), ('ing', ''),
    // Adjectives
    ('er', ''), ('est', ''), ('er', 'e'), ('est', 'e'),
  ];

  /// The selection as a dictionary would list it, or null if it can't be a word
  /// or short phrase, such as a whole sentence selected to copy.
  static String? normalize(String selection) {
    var text = selection
        .replaceAll(RegExp(r'[‘’ʼ]'), "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();
    text = text
        .replaceFirst(RegExp(r"^[^\p{L}\p{N}]+", unicode: true), '')
        .replaceFirst(RegExp(r"[^\p{L}\p{N}]+$", unicode: true), '');
    text = text.replaceFirst(RegExp(r"'s$"), '');
    if (text.isEmpty || text.length > _maxLength) return null;
    if (text.split(' ').length > maxWords) return null;
    return text;
  }

  /// Possible headwords for a normalized word, most likely first.
  static List<String> stems(String word) {
    final found = <String>[word];
    for (final (suffix, replacement) in _rules) {
      if (word.length > suffix.length && word.endsWith(suffix)) {
        final stem =
            word.substring(0, word.length - suffix.length) + replacement;
        if (!found.contains(stem)) found.add(stem);
      }
    }
    return found;
  }
}
