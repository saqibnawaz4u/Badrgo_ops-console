import 'package:equatable/equatable.dart';

/// One `resource:action` pair, e.g. `trip:assign`.
class Permission extends Equatable {
  const Permission(this.resource, this.action);

  final String resource;
  final String action;

  static const kpiRead = Permission('kpi', 'read');
  static const tripRead = Permission('trip', 'read');
  static const tripCreate = Permission('trip', 'create');
  static const tripAssign = Permission('trip', 'assign');
  static const tripCancel = Permission('trip', 'cancel');
  static const tripRefund = Permission('trip', 'refund');
  static const driverRead = Permission('driver', 'read');
  static const driverTrack = Permission('driver', 'track');
  static const driverMessage = Permission('driver', 'message');
  static const alertRead = Permission('alert', 'read');
  static const alertAcknowledge = Permission('alert', 'acknowledge');
  static const userList = Permission('user', 'list');
  static const userCreate = Permission('user', 'create');
  static const userSetRole = Permission('user', 'set-role');
  static const userBan = Permission('user', 'ban');
  static const piiRead = Permission('pii', 'read');

  @override
  List<Object?> get props => [resource, action];

  @override
  String toString() => '$resource:$action';
}

/// The permission map from `GET /api/me`. The whole UI is driven by this,
/// never by the role name.
class Permissions extends Equatable {
  const Permissions(this._grants);

  static const none = Permissions({});

  final Map<String, Set<String>> _grants;

  /// Accepts the REST shape `{ "trip": ["read", ...] }`.
  factory Permissions.fromJson(Object? json) {
    if (json is! Map) return none;
    return Permissions({
      for (final entry in json.entries)
        if (entry.value is List)
          '${entry.key}': {for (final a in entry.value as List) '$a'},
    });
  }

  bool can(Permission permission) {
    final actions = _grants[permission.resource];
    if (actions == null) return false;
    return actions.contains(permission.action) || actions.contains('*');
  }

  bool canAll(Iterable<Permission> permissions) => permissions.every(can);

  bool canAny(Iterable<Permission> permissions) => permissions.any(can);

  Map<String, Set<String>> toMap() => {
        for (final e in _grants.entries) e.key: Set.unmodifiable(e.value),
      };

  @override
  List<Object?> get props => [
        // Order-independent equality so a refreshed /api/me with the same
        // grants does not look like a permission change.
        {for (final e in _grants.entries) e.key: (e.value.toList()..sort()).join(',')}
            .entries
            .map((e) => '${e.key}=${e.value}')
            .toList()
          ..sort(),
      ];
}
