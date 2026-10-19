import 'dart:async';

import '../connectivity/domain/maintenance_info.dart';

/// Cross-cutting signals raised by every transport (REST, GraphQL, SSE,
/// WebSocket). The app layer listens and reacts in one place:
/// 401 → sign out, 403 → re-fetch `/api/me`, 503 → maintenance state,
/// network failure → offline banner.
class SessionSignals {
  final _unauthorized = StreamController<void>.broadcast();
  final _forbidden = StreamController<void>.broadcast();
  final _maintenance = StreamController<MaintenanceInfo>.broadcast();
  final _networkFailure = StreamController<void>.broadcast();

  Stream<void> get unauthorized => _unauthorized.stream;
  Stream<void> get forbidden => _forbidden.stream;
  Stream<MaintenanceInfo> get maintenance => _maintenance.stream;
  Stream<void> get networkFailure => _networkFailure.stream;

  void reportUnauthorized() => _unauthorized.add(null);
  void reportForbidden() => _forbidden.add(null);
  void reportMaintenance(MaintenanceInfo info) => _maintenance.add(info);
  void reportNetworkFailure() => _networkFailure.add(null);

  Future<void> dispose() async {
    await Future.wait([
      _unauthorized.close(),
      _forbidden.close(),
      _maintenance.close(),
      _networkFailure.close(),
    ]);
  }
}
