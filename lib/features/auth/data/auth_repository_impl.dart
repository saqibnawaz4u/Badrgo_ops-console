import '../../../core/domain/shared_entities.dart';
import '../../../core/error/api_exception.dart';
import '../../../core/network/rest_client.dart';
import '../../../core/network/token_store.dart';
import '../../../core/permissions/permissions.dart';
import '../domain/entities/current_user.dart';
import '../domain/repositories/auth_repository.dart';

/// REST only: sign-in, sign-out and `/api/me`.
class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this._rest, this._tokens);

  final RestClient _rest;
  final TokenStore _tokens;

  @override
  String? get token => _tokens.token;

  @override
  String? restoreToken() => _tokens.restore();

  @override
  Future<CurrentUser> signIn({required String email, required String password}) async {
    final body = await _rest.post(
      '/api/auth/sign-in/email',
      body: {'email': email.trim(), 'password': password},
      authenticated: false,
    );
    final token = body is Map ? body['token'] as String? : null;
    if (token == null || token.isEmpty) {
      throw const ApiException(ApiErrorCode.unknown, 'Sign-in did not return a session.');
    }
    await _tokens.save(token);
    try {
      return await fetchMe();
    } on Object {
      await _tokens.clear();
      rethrow;
    }
  }

  @override
  Future<CurrentUser> fetchMe() async => meFromJson(await _rest.get('/api/me'));

  @override
  Future<void> signOut() async {
    try {
      await _rest.post('/api/auth/sign-out');
    } on ApiException {
      // The token may already be revoked or the API down; sign out locally anyway.
    } finally {
      await _tokens.clear();
    }
  }

  @override
  Future<void> clearLocalSession() => _tokens.clear();

  static CurrentUser meFromJson(Object? json) {
    if (json is! Map) {
      throw const ApiException(ApiErrorCode.unknown, 'Unexpected /api/me response.');
    }
    final user = json['user'] as Map? ?? const {};
    return CurrentUser(
      id: '${user['id']}',
      name: (user['name'] as String?) ?? '',
      email: (user['email'] as String?) ?? '',
      role: (json['role'] as String?) ?? '',
      roleDescription: (json['roleDescription'] as String?) ?? '',
      city: City.fromJson(json['city']),
      permissions: Permissions.fromJson(json['permissions']),
    );
  }
}
