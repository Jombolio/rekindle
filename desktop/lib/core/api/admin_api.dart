import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../import/book_import.dart';
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

  Future<void> updatePassword(String userId, String password) => _client.dio
      .put('api/users/$userId/password', data: {'password': password});

  Future<void> deleteUser(String userId) =>
      _client.dio.delete('api/users/$userId');

  Future<String> uploadFile({
    required String libraryId,
    String? relativePath,
    required String filePath,
    required String fileName,
    bool deferScan = false,
    CancelToken? cancelToken,
    void Function(int sent, int total)? onProgress,
  }) async {
    final formData = FormData.fromMap({
      'libraryId': libraryId,
      if (relativePath != null && relativePath.isNotEmpty)
        'relativePath': relativePath,
      if (deferScan) 'deferScan': 'true',
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
    });

    final resp = await _client.dio.post(
      'api/admin/upload',
      data: formData,
      cancelToken: cancelToken,
      onSendProgress: onProgress,
      options: Options(
        sendTimeout: const Duration(minutes: 30),
        receiveTimeout: const Duration(minutes: 5),
      ),
    );
    final data = resp.data as Map<String, dynamic>;
    return data['message'] as String? ?? 'Upload complete.';
  }

  /// Asks whether a book can be imported, from the start of its file.
  Future<BookInspection> inspectBook({
    required String libraryId,
    required String fileName,
    Uint8List? head,
    String? title,
    String? author,
  }) async {
    final formData = FormData.fromMap({
      'libraryId': libraryId,
      'fileName': fileName,
      if (title != null) 'title': title,
      if (author != null) 'author': author,
      if (head != null) 'head': MultipartFile.fromBytes(head, filename: 'head'),
    });
    final resp =
        await _client.dio.post('api/admin/upload/inspect', data: formData);
    final data = resp.data as Map<String, dynamic>;
    return BookInspection(
      status: ImportStatus.fromServer(data['status'] as String?),
      title: data['title'] as String?,
      author: data['author'] as String?,
      reason: data['reason'] as String?,
    );
  }

  Future<int> clearCache() async {
    final resp = await _client.dio.delete('api/admin/cache');
    final data = resp.data as Map<String, dynamic>;
    return data['freedBytes'] as int? ?? 0;
  }

  /// Every library with its scan schedule. Servers before 1.5.1-beta.8 answer
  /// 404, as they have no schedules.
  Future<List<ScanScheduleInfo>> getScanSchedules() async {
    final resp = await _client.dio.get('api/admin/scan-schedules');
    return (resp.data as List<dynamic>)
        .map((e) => ScanScheduleInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Scans [libraryId] every [intervalHours]; 0 turns scheduled scans off.
  Future<ScanScheduleInfo> setScanSchedule(
      String libraryId, int intervalHours) async {
    final resp = await _client.dio.put(
      'api/admin/scan-schedules/$libraryId',
      data: {'intervalHours': intervalHours},
    );
    return ScanScheduleInfo.fromJson(resp.data as Map<String, dynamic>);
  }
}

/// A library and how often it's scanned on its own.
class ScanScheduleInfo {
  final String libraryId;
  final String libraryName;

  /// Hours between scheduled scans; 0 when there are none.
  final int intervalHours;
  final DateTime? lastRunAt;
  final DateTime? nextRunAt;

  const ScanScheduleInfo({
    required this.libraryId,
    required this.libraryName,
    required this.intervalHours,
    this.lastRunAt,
    this.nextRunAt,
  });

  factory ScanScheduleInfo.fromJson(Map<String, dynamic> j) => ScanScheduleInfo(
        libraryId: j['libraryId'] as String,
        libraryName: j['libraryName'] as String? ?? '',
        intervalHours: j['intervalHours'] as int? ?? 0,
        lastRunAt: _time(j['lastRunAt']),
        nextRunAt: _time(j['nextRunAt']),
      );

  // The server writes UTC; shown in local time.
  static DateTime? _time(Object? v) => v is String
      ? DateTime.tryParse(v.endsWith('Z') || v.contains('+') ? v : '${v}Z')
          ?.toLocal()
      : null;
}
