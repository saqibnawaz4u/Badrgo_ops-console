import 'package:equatable/equatable.dart';

import '../../../../core/domain/shared_entities.dart';
import '../../../../core/permissions/permissions.dart';

/// The signed-in user as returned by `GET /api/me`.
class CurrentUser extends Equatable {
  const CurrentUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.roleDescription,
    required this.city,
    required this.permissions,
  });

  final String id;
  final String name;
  final String email;

  /// Raw role, e.g. `ops_manager`. For display only: access decisions use
  /// [permissions].
  final String role;
  final String roleDescription;

  /// Null for super_admin (all cities).
  final City? city;
  final Permissions permissions;

  String get roleLabel => role
      .split('_')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  String get cityLabel => city?.name ?? 'All cities';

  @override
  List<Object?> get props => [id, name, email, role, roleDescription, city, permissions];
}
