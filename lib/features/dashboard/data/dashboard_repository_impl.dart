import '../../../core/domain/shared_entities.dart';
import '../../../core/network/graphql_client.dart';
import '../../../core/realtime/server_events.dart';
import '../domain/entities/kpis.dart';
import '../domain/repositories/dashboard_repository.dart';

class DashboardRepositoryImpl implements DashboardRepository {
  DashboardRepositoryImpl({required GraphQLClient graphQL, required ServerEvents events})
    : _graphQL = graphQL,
      _events = events;

  final GraphQLClient _graphQL;
  final ServerEvents _events;

  static const _query = r'''
    query Kpis($range: KpiRange) {
      kpis(range: $range) {
        range generatedAt
        trips { requested assigned inProgress completed cancelled active cancellationRate }
        revenue { amount currency }
        averageFare { amount currency }
        refunds { amount currency }
        drivers { available onTrip offline total }
        openAlerts
        series { bucket total completed cancelled }
        topDrivers { driver { id name } trips earnings { amount currency } }
      }
    }
  ''';

  @override
  Future<Kpis> fetchKpis(KpiRange range) async {
    final data = await _graphQL.query(_query, variables: {'range': range.graphQLName});
    return KpiMapper.fromJson(data['kpis'] as Map<String, dynamic>);
  }

  @override
  Stream<Kpis> watchKpis() => _events.on('kpi').map((e) => KpiMapper.fromJson(e.data));
}

/// Same payload from GraphQL (`LAST_24H`, nested `driver`) and SSE
/// (`last_24h`, flat `driverId`).
class KpiMapper {
  const KpiMapper._();

  static Kpis fromJson(Map<String, dynamic> json) {
    final trips = json['trips'] as Map<String, dynamic>? ?? const {};
    final drivers = json['drivers'] as Map<String, dynamic>? ?? const {};
    int i(Map<String, dynamic> m, String k) => (m[k] as num?)?.toInt() ?? 0;
    return Kpis(
      range: '${json['range']}'.toUpperCase() == KpiRange.last7d.graphQLName ? KpiRange.last7d : KpiRange.last24h,
      generatedAt: parseDate(json['generatedAt']) ?? DateTime.now(),
      trips: TripCounts(
        requested: i(trips, 'requested'),
        assigned: i(trips, 'assigned'),
        inProgress: i(trips, 'inProgress'),
        completed: i(trips, 'completed'),
        cancelled: i(trips, 'cancelled'),
        active: i(trips, 'active'),
        cancellationRate: (trips['cancellationRate'] as num?)?.toDouble() ?? 0,
      ),
      revenue: Money.listFromJson(json['revenue']),
      averageFare: Money.listFromJson(json['averageFare']),
      refunds: Money.listFromJson(json['refunds']),
      drivers: DriverCounts(
        available: i(drivers, 'available'),
        onTrip: i(drivers, 'onTrip'),
        offline: i(drivers, 'offline'),
        total: i(drivers, 'total'),
      ),
      openAlerts: (json['openAlerts'] as num?)?.toInt() ?? 0,
      series: [
        for (final p in (json['series'] as List? ?? const []))
          if (p is Map<String, dynamic>)
            SeriesPoint(
              bucket: parseDate(p['bucket']) ?? DateTime.now(),
              total: i(p, 'total'),
              completed: i(p, 'completed'),
              cancelled: i(p, 'cancelled'),
            ),
      ],
      topDrivers: [
        for (final d in (json['topDrivers'] as List? ?? const []))
          if (d is Map<String, dynamic>)
            TopDriver(
              driverId: '${(d['driver'] as Map?)?['id'] ?? d['driverId']}',
              name: (d['driver'] as Map?)?['name'] as String?,
              trips: i(d, 'trips'),
              earnings: Money.fromJson(d['earnings']),
            ),
      ],
    );
  }
}
