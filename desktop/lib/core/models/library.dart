class Library {
  final String id;
  final String name;
  final String rootPath;
  final String type;

  const Library({
    required this.id,
    required this.name,
    required this.rootPath,
    required this.type,
  });

  factory Library.fromJson(Map<String, dynamic> j) => Library(
        id: j['id'] as String,
        name: j['name'] as String,
        rootPath: j['rootPath'] as String,
        type: j['type'] as String,
      );

  String get typeLabel => switch (type) {
        'comic' => 'Comics',
        'manga' => 'Manga',
        'book' => 'Books',
        _ => type,
      };
}
