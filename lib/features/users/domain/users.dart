import 'package:equatable/equatable.dart';

import '../../../core/domain/shared_entities.dart';

/// Roles the API accepts when creating or re-roling a user. This is form
/// data, not access logic: the UI never branches on these names.
const assignableRoles = ['super_admin', 'ops_manager', 'dispatcher', 'support', 'viewer'];

class AppUser extends Equatable {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.cityId,
    required this.banned,
    this.banReason,
  });

  final String id;
  final String name;
  final String email;
  final String role;
  final String? cityId;
  final bool banned;
  final String? banReason;

  /// The shared demo accounts must not be edited (see the brief); the UI
  /// asks for explicit confirmation before touching one.
  bool get isDemoAccount => email.toLowerCase().endsWith('@demo.test');

  @override
  List<Object?> get props => [id, name, email, role, cityId, banned, banReason];
}

class UsersResult extends Equatable {
  const UsersResult({required this.users, required this.page, required this.totalPages, required this.total});

  final List<AppUser> users;
  final int page;
  final int totalPages;
  final int total;

  @override
  List<Object?> get props => [users, page, totalPages, total];
}

class NewUser {
  const NewUser({
    required this.name,
    required this.email,
    required this.password,
    required this.role,
    this.cityId,
  });

  final String name;
  final String email;
  final String password;
  final String role;
  final String? cityId;
}

abstract interface class UsersRepository {
  Future<UsersResult> fetchUsers({int page = 1, String? search});
  Future<List<City>> fetchCities();
  Future<AppUser> create(NewUser user);
  Future<AppUser> update(String id, {String? role, String? cityId});
  Future<AppUser> ban(String id, String reason);
  Future<AppUser> unban(String id);
}
