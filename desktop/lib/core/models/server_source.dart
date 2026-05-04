class ServerSource {
  final String id;
  final String name;
  final String baseUrl;
  final String? token;

  const ServerSource({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.token,
  });

  factory ServerSource.create({
    required String name,
    required String baseUrl,
    String? token,
  }) =>
      ServerSource(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        baseUrl: baseUrl,
        token: token,
      );

  ServerSource copyWith({
    String? name,
    String? baseUrl,
    String? token,
    bool clearToken = false,
  }) =>
      ServerSource(
        id: id,
        name: name ?? this.name,
        baseUrl: baseUrl ?? this.baseUrl,
        token: clearToken ? null : (token ?? this.token),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        if (token != null) 'token': token,
      };

  factory ServerSource.fromJson(Map<String, dynamic> json) => ServerSource(
        id: json['id'] as String,
        name: json['name'] as String,
        baseUrl: json['baseUrl'] as String,
        token: json['token'] as String?,
      );
}
