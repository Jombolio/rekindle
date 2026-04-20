import 'package:dio/dio.dart';

class ApiClient {
  final String baseUrl;
  final String? token;
  late final Dio dio;

  ApiClient({required this.baseUrl, this.token}) {
    dio = Dio(BaseOptions(
      baseUrl: baseUrl.endsWith('/') ? baseUrl : '$baseUrl/',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    ));

    dio.interceptors.add(LogInterceptor(responseBody: false));
  }

  /// Returns the full URL for a media page image — used by image widgets.
  String pageUrl(String mediaId, int page) =>
      '${baseUrl.endsWith('/') ? baseUrl : '$baseUrl/'}'
      'api/media/$mediaId/page/$page';

  /// Returns the full URL for a media cover — used by image widgets.
  String coverUrl(String mediaId) =>
      '${baseUrl.endsWith('/') ? baseUrl : '$baseUrl/'}'
      'api/media/$mediaId/cover';

  Map<String, String> get authHeaders =>
      token != null ? {'Authorization': 'Bearer $token'} : {};
}
