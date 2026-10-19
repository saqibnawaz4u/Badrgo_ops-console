import '../entities/kpis.dart';

abstract interface class DashboardRepository {
  /// GraphQL `kpis(range:)`, scoped to the caller's city.
  Future<Kpis> fetchKpis(KpiRange range);

  /// SSE `kpi` ticks (every ~5 s, last 24 h).
  Stream<Kpis> watchKpis();
}
