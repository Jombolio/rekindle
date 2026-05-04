import 'package:dio/dio.dart';

import 'api_client.dart';

class AdminStats {
  final int userCount;
  final int libraryCount;
  final int mediaCount;
  final int cacheSizeBytes;

  const AdminStats({
    required this.userCount,
    required this.libraryCount,
    required this.mediaCount,
    required this.cacheSizeBytes,
  });

  factory AdminStats.fromJson(Map<String, dynamic> j) => AdminStats(
        userCount: j['userCount'] as int,
        libraryCount: j['libraryCount'] as int,
        mediaCount: j['mediaCount'] as int,
        cacheSizeBytes: j['cacheSizeBytes'] as int,
      );

  String get cacheSizeLabel {
    final mb = cacheSizeBytes / (1024 * 1024);
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    return '${(mb / 1024).toStringAsFixed(2)} GB';
  }
}

class AdminUser {
  final String id;
  final String username;
  final int permissionLevel;
  final DateTime createdAt;

  const AdminUser({
    required this.id,
    required this.username,
    required this.permissionLevel,
    required this.createdAt,
  });

  bool get isAdmin => permissionLevel >= 4;

  String get permissionLabel => switch (permissionLevel) {
        1 => 'Read-only',
        2 => 'Download',
        3 => 'Manage Media',
        4 => 'Admin',
        _ => 'Unknown',
      };

  factory AdminUser.fromJson(Map<String, dynamic> j) => AdminUser(
        id: j['id'] as String,
        username: j['username'] as String,
        permissionLevel: j['permissionLevel'] as int,
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
}

class AdminApi {
  const AdminApi(this._client);
  final ApiClient _client;

  Future<AdminStats> getStats() async {
    final resp = await _client.dio.get('api/admin/stats');
    return AdminStats.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<List<AdminUser>> getUsers() async {
    final resp = await _client.dio.get('api/users');
    return (resp.data as List<dynamic>)
        .map((e) => AdminUser.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<AdminUser> createUser({
    required String username,
    required String password,
    required int permissionLevel,
  }) async {
    final resp = await _client.dio.post('api/users', data: {
      'username': username,
      'password': password,
      'permissionLevel': permissionLevel,
    });
    return AdminUser.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<void> updatePermission(String userId, int permissionLevel) =>
      _client.dio.put('api/users/$userId/permission',
          data: {'permissionLevel': permissionLevel});

  Future<void> updatePassword(String userId, String password) =>
      _client.dio
          .put('api/users/$userId/password', data: {'password': password});

  Future<void> deleteUser(String userId) =>
      _client.dio.delete('api/users/$userId');

  Future<String> uploadFile({
    required String libraryId,
    String? relativePath,
    required String filePath,
    required String fileName,
    void Function(int sent, int total)? onProgress,
  }) async {
    final formData = FormData.fromMap({
      'libraryId': libraryId,
      if (relativePath != null && relativePath.isNotEmpty) 'relativePath': relativePath,
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
    });

    final resp = await _client.dio.post(
      'api/admin/upload',
      data: formData,
      onSendProgress: onProgress,
      options: Options(
        sendTimeout: const Duration(minutes: 30),
        receiveTimeout: const Duration(minutes: 5),
      ),
    );
    final data = resp.data as Map<String, dynamic>;
    return data['message'] as String? ?? 'Upload complete.';
  }

  Future<int> clearCache() async {
    final resp = await _client.dio.delete('api/admin/cache');
    final data = resp.data as Map<String, dynamic>;
    return data['freedBytes'] as int? ?? 0;
  }
}
