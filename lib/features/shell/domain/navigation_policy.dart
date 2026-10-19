import '../../../core/permissions/permissions.dart';

enum AppSection { dashboard, trips, liveMap, alerts, users }

class NavDestination {
  const NavDestination(this.section, this.path, this.label, this.required);

  final AppSection section;
  final String path;
  final String label;
  final Permission required;
}

/// Which sections exist and which permission unlocks each. The shell,
/// the router and the home redirect all read from here, so a section is
/// visible exactly when its route is reachable.
class NavigationPolicy {
  const NavigationPolicy();

  static const destinations = [
    NavDestination(AppSection.dashboard, '/dashboard', 'Dashboard', Permission.kpiRead),
    NavDestination(AppSection.trips, '/trips', 'Trips', Permission.tripRead),
    NavDestination(AppSection.liveMap, '/map', 'Live map', Permission.driverTrack),
    NavDestination(AppSection.alerts, '/alerts', 'Alerts', Permission.alertRead),
    NavDestination(AppSection.users, '/users', 'Users', Permission.userList),
  ];

  List<NavDestination> visibleFor(Permissions permissions) =>
      destinations.where((d) => permissions.can(d.required)).toList();

  /// Where to land after sign-in or on `/`. Null if the user can see nothing.
  String? homePathFor(Permissions permissions) {
    final visible = visibleFor(permissions);
    return visible.isEmpty ? null : visible.first.path;
  }

  /// The section that owns [location] (`/trips/abc` → trips), if any.
  NavDestination? sectionFor(String location) {
    final path = Uri.parse(location).path;
    for (final d in destinations) {
      if (path == d.path || path.startsWith('${d.path}/')) return d;
    }
    return null;
  }

  bool canOpen(String location, Permissions permissions) {
    final section = sectionFor(location);
    return section == null || permissions.can(section.required);
  }

  /// SSE topics worth asking for. The server would drop the others anyway
  /// (listed in `deniedTopics`); asking only for what we can read keeps the
  /// stream quiet and the intent explicit.
  List<String> realtimeTopicsFor(Permissions permissions) => [
        if (permissions.can(Permission.kpiRead)) 'kpi',
        if (permissions.can(Permission.alertRead)) 'alerts',
        if (permissions.can(Permission.tripRead)) 'trips',
        if (permissions.can(Permission.driverRead)) 'drivers',
      ];

  bool needsDriverSocket(Permissions permissions) =>
      permissions.canAny(const [Permission.driverTrack, Permission.driverMessage]);
}
