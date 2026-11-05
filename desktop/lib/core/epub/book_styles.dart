/// The subset of a book's CSS the reader applies.
///
/// The HTML widget only understands inline styles, so stylesheet rules are
/// matched here and handed to it per element. Only layout and emphasis carry
/// over: colours, fonts and line spacing stay under the reader's control.
class BookStyles {
  static const empty = BookStyles._({}, {});

  static const _keptProperties = {
    'display',
    'font-style',
    'font-weight',
    'margin',
    'margin-bottom',
    'margin-left',
    'margin-right',
    'margin-top',
    'text-align',
    'text-decoration',
    'text-indent',
    'vertical-align',
  };

  final Map<String, Map<String, String>> _byTag;
  final Map<String, Map<String, String>> _byClass;

  const BookStyles._(this._byTag, this._byClass);

  /// Rules whose selector is a tag and/or classes are kept; a descendant
  /// selector counts as its last part. Anything more specific is ignored rather
  /// than guessed at.
  factory BookStyles.parse(String css) {
    final byTag = <String, Map<String, String>>{};
    final byClass = <String, Map<String, String>>{};

    final text = css.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), ' ');
    for (final rule in RegExp(r'([^{}]+)\{([^{}]*)\}').allMatches(text)) {
      final declarations = _parseDeclarations(rule.group(2)!);
      if (declarations.isEmpty) continue;

      for (final selector in rule.group(1)!.split(',')) {
        final trimmed = selector.trim();
        if (trimmed.isEmpty || trimmed.contains('@')) continue;
        final last = trimmed.split(RegExp(r'[\s>+~]+')).last;
        final match =
            RegExp(r'^([a-zA-Z][\w-]*)?((?:\.[\w-]+)*)$').firstMatch(last);
        if (match == null) continue;

        final tag = match.group(1)?.toLowerCase();
        final classes = match
            .group(2)!
            .split('.')
            .where((c) => c.isNotEmpty)
            .toList();
        if (classes.isNotEmpty) {
          for (final c in classes) {
            (byClass[c] ??= {}).addAll(declarations);
          }
        } else if (tag != null) {
          (byTag[tag] ??= {}).addAll(declarations);
        }
      }
    }
    return BookStyles._(byTag, byClass);
  }

  static Map<String, String> _parseDeclarations(String block) {
    final result = <String, String>{};
    for (final declaration in block.split(';')) {
      final colon = declaration.indexOf(':');
      if (colon < 0) continue;
      final property = declaration.substring(0, colon).trim().toLowerCase();
      final value = declaration
          .substring(colon + 1)
          .replaceAll(RegExp(r'!important', caseSensitive: false), '')
          .trim();
      if (value.isEmpty || !_keptProperties.contains(property)) continue;
      // Other display values depend on layout the widget doesn't do.
      if (property == 'display' && value != 'none') continue;
      result[property] = value;
    }
    return result;
  }

  /// Styles for an element, with class rules overriding tag rules.
  Map<String, String> stylesFor(String tag, Iterable<String> classes) {
    final tagRules = _byTag[tag.toLowerCase()];
    final classRules = classes.map((c) => _byClass[c]).whereType<Map<String, String>>();
    if (tagRules == null && classRules.isEmpty) return const {};
    return {
      ...?tagRules,
      for (final rules in classRules) ...rules,
    };
  }
}
