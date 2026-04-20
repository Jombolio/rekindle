import 'api_client.dart';

class AuthResult {
  final String token;
  final String username;
  final int permissionLevel;

  const AuthResult({
    required this.token,
    required this.username,
    required this.permissionLevel,
  });

  factory AuthResult.fromJson(Map<String, dynamic> j) => AuthResult(
        token: j['token'] as String,
        username: j['username'] as String,
        permissionLevel: j['permissionLevel'] as int? ?? 2,
      );
}

class AuthApi {
  const AuthApi(this._client);
  final ApiClient _client;

  Future<AuthResult> login(String username, String password) async {
    final resp = await _client.dio.post('api/auth/login', data: {
      'username': username,
      'password': password,
    });
    return AuthResult.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<AuthResult> setup(String username, String password, String setupToken) async {
    final resp = await _client.dio.post('api/auth/setup', data: {
      'username': username,
      'password': password,
      'setupToken': setupToken,
    });
    return AuthResult.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> me() async {
    final resp = await _client.dio.get('api/auth/me');
    return resp.data as Map<String, dynamic>;
  }
}
