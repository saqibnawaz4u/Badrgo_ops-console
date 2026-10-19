import 'package:badrgo_ops_console/core/domain/shared_entities.dart';
import 'package:badrgo_ops_console/core/permissions/permissions.dart';
import 'package:badrgo_ops_console/features/auth/domain/entities/current_user.dart';

/// `permissions` exactly as `GET /api/me` returned them for the sandbox
/// demo accounts (captured 2026-10-19).
const rolePermissionJson = <String, Map<String, List<String>>>{
  'super_admin': {
    'user': ['create', 'list', 'set-role', 'ban', 'impersonate', 'delete', 'set-password', 'set-email', 'get', 'update'],
    'session': ['list', 'revoke', 'delete'],
    'city': ['read', 'create', 'update'],
    'driver': ['read', 'create', 'update', 'track', 'message'],
    'rider': ['read', 'create', 'update'],
    'trip': ['read', 'create', 'assign', 'cancel', 'refund'],
    'alert': ['read', 'acknowledge'],
    'kpi': ['read'],
    'pii': ['read'],
    'simulator': ['control'],
  },
  'ops_manager': {
    'city': ['read'],
    'driver': ['read', 'create', 'update', 'track', 'message'],
    'rider': ['read', 'create', 'update'],
    'trip': ['read', 'create', 'assign', 'cancel', 'refund'],
    'alert': ['read', 'acknowledge'],
    'kpi': ['read'],
    'pii': ['read'],
  },
  'dispatcher': {
    'city': ['read'],
    'driver': ['read', 'track', 'message'],
    'rider': ['read'],
    'trip': ['read', 'create', 'assign', 'cancel'],
    'alert': ['read', 'acknowledge'],
    'kpi': ['read'],
    'pii': ['read'],
  },
  'support': {
    'city': ['read'],
    'driver': ['read'],
    'rider': ['read', 'update'],
    'trip': ['read', 'refund'],
    'alert': ['read', 'acknowledge'],
    'pii': ['read'],
  },
  'viewer': {
    'city': ['read'],
    'driver': ['read'],
    'rider': ['read'],
    'trip': ['read'],
    'alert': ['read'],
    'kpi': ['read'],
  },
};

Permissions permissionsFor(String role) => Permissions.fromJson(rolePermissionJson[role]);

CurrentUser userFor(String role) => CurrentUser(
      id: 'usr_$role',
      name: 'Test $role',
      email: '$role@demo.test',
      role: role,
      roleDescription: role,
      city: role == 'super_admin' ? null : const City(id: 'doha', name: 'Doha'),
      permissions: permissionsFor(role),
    );
