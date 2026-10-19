import 'package:badrgo_ops_console/core/permissions/permissions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Permissions.fromJson', () {
    test('reads the /api/me map of resource to actions', () {
      final p = Permissions.fromJson({
        'trip': ['read', 'assign'],
        'kpi': ['read'],
      });

      expect(p.can(Permission.tripRead), isTrue);
      expect(p.can(Permission.tripAssign), isTrue);
      expect(p.can(Permission.kpiRead), isTrue);
      expect(p.can(Permission.tripRefund), isFalse);
      expect(p.can(Permission.alertRead), isFalse);
    });

    test('anything that is not a map grants nothing', () {
      for (final json in [null, 'admin', 42, <Object>[]]) {
        expect(Permissions.fromJson(json), Permissions.none);
        expect(Permissions.fromJson(json).can(Permission.tripRead), isFalse);
      }
    });

    test('ignores malformed entries instead of failing', () {
      final p = Permissions.fromJson({'trip': 'read', 'kpi': ['read']});

      expect(p.can(Permission.tripRead), isFalse);
      expect(p.can(Permission.kpiRead), isTrue);
    });
  });

  test('a "*" action grants every action on that resource only', () {
    final p = Permissions.fromJson({
      'trip': ['*'],
    });

    expect(p.can(Permission.tripAssign), isTrue);
    expect(p.can(Permission.tripRefund), isTrue);
    expect(p.can(Permission.kpiRead), isFalse);
  });

  test('canAll and canAny', () {
    final p = Permissions.fromJson({
      'driver': ['track'],
    });

    expect(p.canAny(const [Permission.driverTrack, Permission.driverMessage]), isTrue);
    expect(p.canAll(const [Permission.driverTrack, Permission.driverMessage]), isFalse);
  });

  test('equality ignores order, so an unchanged /api/me is not a role change', () {
    final a = Permissions.fromJson({
      'trip': ['read', 'assign'],
      'kpi': ['read'],
    });
    final b = Permissions.fromJson({
      'kpi': ['read'],
      'trip': ['assign', 'read'],
    });
    final c = Permissions.fromJson({
      'trip': ['read'],
      'kpi': ['read'],
    });

    expect(a, b);
    expect(a, isNot(c));
  });
}
