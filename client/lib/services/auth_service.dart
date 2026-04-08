import '../models/user.dart';
import 'api_client.dart';

class AuthService {
  final ApiClient _api;

  AuthService(this._api);

  Future<AuthResponse> register({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final response = await _api.dio.post('/api/auth/register', data: {
      'email': email,
      'password': password,
      if (displayName != null) 'display_name': displayName,
    });
    final authResponse = AuthResponse.fromJson(response.data);
    await _api.setToken(authResponse.token);
    return authResponse;
  }

  Future<AuthResponse> login({
    required String email,
    required String password,
  }) async {
    final response = await _api.dio.post('/api/auth/login', data: {
      'email': email,
      'password': password,
    });
    final authResponse = AuthResponse.fromJson(response.data);
    await _api.setToken(authResponse.token);
    return authResponse;
  }

  Future<User> me() async {
    final response = await _api.dio.get('/api/auth/me');
    return User.fromJson(response.data);
  }

  Future<void> logout() async {
    await _api.clearToken();
  }
}
