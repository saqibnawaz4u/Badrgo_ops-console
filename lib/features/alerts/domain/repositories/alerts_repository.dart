import '../entities/alert.dart';

abstract interface class AlertsRepository {
  /// GraphQL `alerts`, newest first.
  Future<AlertPage> fetchAlerts({
    bool? acknowledged,
    bool criticalOnly = false,
    String? after,
    int first = 30,
  });

  /// SSE `alert.created` and `alert.acknowledged`.
  Stream<AlertChange> watchChanges();

  /// REST `POST /api/alerts/{id}/acknowledge`.
  Future<void> acknowledge(String id);
}
