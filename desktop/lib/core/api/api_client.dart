import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Response header carrying a replacement JWT, issued by the server shortly
/// before the current one expires.
const tokenRenewalHeader = 'x-rekindle-token';

class ApiClient {
  final String baseUrl;
  final String? token;
  final void Function()? onUnauthorized;
  final void Function(String token)? onTokenRenewed;
  late final Dio dio;

  /// Authenticated client for a configured source.
  ///
  /// [onUnauthorized] and [onTokenRenewed] are required rather than optional
  /// because a client built without them silently opts out of session recovery:
  /// an expired token then surfaces as a raw error while the dead token stays on
  /// disk, so nothing ever prompts a re-login. Prefer `clientForSource` in
  /// `providers/auth_provider.dart`, which wires both to the right source.
  ApiClient({
    required this.baseUrl,
    required this.token,
    required this.onUnauthorized,
    required this.onTokenRenewed,
  }) {
    _init();
  }

  /// Client for login, setup and reachability probes — calls that carry no
  /// session, where a 401 means "wrong credentials" rather than "session lost"
  /// and so must not clear anything.
  ApiClient.anonymous({required this.baseUrl})
      : token = null,
        onUnauthorized = null,
        onTokenRenewed = null {
    _init();
  }

  void _init() {
    dio = Dio(BaseOptions(
      baseUrl: baseUrl.endsWith('/') ? baseUrl : '$baseUrl/',
      connectTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    ));

    // LogInterceptor prints request headers — including the Authorization
    // bearer token — so keep it out of release builds.
    if (kDebugMode) {
      dio.interceptors.add(LogInterceptor(responseBody: false));
    }
    if (onUnauthorized != null || onTokenRenewed != null) {
      dio.interceptors.add(_SessionInterceptor(onUnauthorized, onTokenRenewed));
    }
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

/// Keeps the stored session in step with what the server says about it: banks a
/// server-issued replacement token, and reports a rejected one so the source can
/// be signed out and its sign-in prompt shown.
class _SessionInterceptor extends Interceptor {
  _SessionInterceptor(this._onUnauthorized, this._onTokenRenewed);

  final void Function()? _onUnauthorized;
  final void Function(String token)? _onTokenRenewed;

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    _bankRenewedToken(response);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // A renewal can ride along on an error response too — don't lose it.
    _bankRenewedToken(err.response);
    if (err.response?.statusCode == 401) {
      _onUnauthorized?.call();
    }
    handler.next(err);
  }

  void _bankRenewedToken(Response<dynamic>? response) {
    final renewed = response?.headers.value(tokenRenewalHeader);
    if (renewed != null && renewed.isNotEmpty) {
      _onTokenRenewed?.call(renewed);
    }
  }
}
