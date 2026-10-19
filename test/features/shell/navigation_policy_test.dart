import 'package:badrgo_ops_console/core/permissions/permissions.dart';
import 'package:badrgo_ops_console/features/shell/domain/navigation_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/roles.dart';

void main() {
  const policy = NavigationPolicy();

  List<AppSection> sectionsFor(String role) =>
      policy.visibleFor(permissionsFor(role)).map((d) => d.section).toList();

  group('visible sections per role', () {
    test('super_admin sees everything, including user admin', () {
      expect(sectionsFor('super_admin'), AppSection.values);
    });

    test('ops_manager and dispatcher: everything except users', () {
      const expected = [AppSection.dashboard, AppSection.trips, AppSection.liveMap, AppSection.alerts];
      expect(sectionsFor('ops_manager'), expected);
      expect(sectionsFor('dispatcher'), expected);
    });

    test('support: no dashboard (no kpi:read) and no live map (no driver:track)', () {
      expect(sectionsFor('support'), [AppSection.trips, AppSection.alerts]);
    });

    test('viewer: dashboard, trips and alerts, but no live map', () {
      expect(sectionsFor('viewer'), [AppSection.dashboard, AppSection.trips, AppSection.alerts]);
    });
  });

  group('home path', () {
    test('lands on the first section the user may see', () {
      expect(policy.homePathFor(permissionsFor('dispatcher')), '/dashboard');
      expect(policy.homePathFor(permissionsFor('support')), '/trips');
    });

    test('null when the user may see nothing', () {
      expect(policy.homePathFor(Permissions.none), isNull);
    });
  });

  group('canOpen (route guard)', () {
    test('nested paths are guarded by their section', () {
      expect(policy.sectionFor('/trips/trp_123')?.section, AppSection.trips);
      expect(policy.canOpen('/trips/trp_123', permissionsFor('viewer')), isTrue);
    });

    test('support typing /map or /dashboard is refused', () {
      final support = permissionsFor('support');
      expect(policy.canOpen('/map', support), isFalse);
      expect(policy.canOpen('/dashboard', support), isFalse);
    });

    test('only super_admin may open /users', () {
      expect(policy.canOpen('/users', permissionsFor('super_admin')), isTrue);
      for (final role in ['ops_manager', 'dispatcher', 'support', 'viewer']) {
        expect(policy.canOpen('/users', permissionsFor(role)), isFalse, reason: role);
      }
    });

    test('a prefix that is not a section boundary does not match', () {
      expect(policy.sectionFor('/tripsx'), isNull);
    });

    test('paths outside any section are not guarded here', () {
      expect(policy.canOpen('/no-access', Permissions.none), isTrue);
    });
  });

  group('realtime', () {
    test('SSE topics follow permissions: support does not ask for kpi', () {
      expect(policy.realtimeTopicsFor(permissionsFor('support')), ['alerts', 'trips', 'drivers']);
      expect(policy.realtimeTopicsFor(permissionsFor('dispatcher')), ['kpi', 'alerts', 'trips', 'drivers']);
    });

    test('the driver WebSocket opens only for track or message', () {
      expect(policy.needsDriverSocket(permissionsFor('dispatcher')), isTrue);
      expect(policy.needsDriverSocket(permissionsFor('support')), isFalse);
      expect(policy.needsDriverSocket(permissionsFor('viewer')), isFalse);
    });
  });
}
