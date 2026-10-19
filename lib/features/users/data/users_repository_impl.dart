import '../../../core/domain/shared_entities.dart';
import '../../../core/network/rest_client.dart';
import '../domain/users.dart';

/// User management is all REST (writes, plus the list that only REST has).
class UsersRepositoryImpl implements UsersRepository {
  UsersRepositoryImpl(this._rest);

  final RestClient _rest;

  @override
  Future<UsersResult> fetchUsers({int page = 1, String? search}) async {
    final body = await _rest.get('/api/users', query: {
      'page': '$page',
      'pageSize': '20',
      'search': search?.trim(),
    }) as Map<String, dynamic>;
    return UsersResult(
      users: [for (final u in body['data'] as List) _user(u as Map<String, dynamic>)],
      page: (body['page'] as num?)?.toInt() ?? page,
      totalPages: (body['totalPages'] as num?)?.toInt() ?? 1,
      total: (body['total'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<List<City>> fetchCities() async {
    final body = await _rest.get('/api/cities');
    final list = body is Map ? body['data'] : body;
    return [for (final c in (list as List)) ?City.fromJson(c)];
  }

  @override
  Future<AppUser> create(NewUser user) async => _user(await _rest.post('/api/users', body: {
        'name': user.name.trim(),
        'email': user.email.trim(),
        'password': user.password,
        'role': user.role,
        'cityId': user.cityId,
      }) as Map<String, dynamic>);

  @override
  Future<AppUser> update(String id, {String? role, String? cityId}) async =>
      _user(await _rest.patch('/api/users/$id', body: {
        'role': ?role,
        'cityId': cityId,
      }) as Map<String, dynamic>);

  @override
  Future<AppUser> ban(String id, String reason) async =>
      _user(await _rest.post('/api/users/$id/ban', body: {'reason': reason.trim()}) as Map<String, dynamic>);

  @override
  Future<AppUser> unban(String id) async =>
      _user(await _rest.post('/api/users/$id/unban') as Map<String, dynamic>);

  static AppUser _user(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        name: '${json['name'] ?? ''}',
        email: '${json['email'] ?? ''}',
        role: '${json['role'] ?? ''}',
        cityId: json['cityId'] as String?,
        banned: json['banned'] == true,
        banReason: json['banReason'] as String?,
      );
}
