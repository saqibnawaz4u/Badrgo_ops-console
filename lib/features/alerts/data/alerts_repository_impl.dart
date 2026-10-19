import '../../../core/domain/shared_entities.dart';
import '../../../core/network/graphql_client.dart';
import '../../../core/network/rest_client.dart';
import '../../../core/realtime/server_events.dart';
import '../../../core/util/streams.dart';
import '../domain/entities/alert.dart';
import '../domain/repositories/alerts_repository.dart';

class AlertsRepositoryImpl implements AlertsRepository {
  AlertsRepositoryImpl({
    required GraphQLClient graphQL,
    required RestClient rest,
    required ServerEvents events,
  })  : _graphQL = graphQL,
        _rest = rest,
        _events = events;

  final GraphQLClient _graphQL;
  final RestClient _rest;
  final ServerEvents _events;

  static const _query = r'''
    query Alerts($filter: AlertFilter, $first: Int, $after: String) {
      alerts(filter: $filter, first: $first, after: $after) {
        totalCount
        pageInfo { endCursor hasNextPage }
        nodes {
          id type severity message createdAt acknowledgedAt acknowledgedBy
          city { id name } trip { id } driver { id name }
        }
      }
    }
  ''';

  @override
  Future<AlertPage> fetchAlerts({
    bool? acknowledged,
    bool criticalOnly = false,
    String? after,
    int first = 30,
  }) async {
    final data = await _graphQL.query(_query, variables: {
      'filter': {
        'acknowledged': ?acknowledged,
        if (criticalOnly) 'severity': ['CRITICAL'],
      },
      'first': first,
      'after': ?after,
    });
    final alerts = data['alerts'] as Map<String, dynamic>;
    final pageInfo = alerts['pageInfo'] as Map<String, dynamic>;
    return AlertPage(
      alerts: [for (final n in alerts['nodes'] as List) alertFromJson(n as Map<String, dynamic>)],
      endCursor: pageInfo['endCursor'] as String?,
      hasNextPage: pageInfo['hasNextPage'] as bool? ?? false,
      totalCount: (alerts['totalCount'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Stream<AlertChange> watchChanges() => mergeStreams([
        _events.on('alert.created').map((e) => _change(e, isNew: true)),
        _events.on('alert.acknowledged').map((e) => _change(e, isNew: false)),
      ]);

  static AlertChange _change(ServerEvent event, {required bool isNew}) =>
      AlertChange(alertFromJson(event.data['alert'] as Map<String, dynamic>), isNew: isNew);

  @override
  Future<void> acknowledge(String id) => _rest.post('/api/alerts/$id/acknowledge');

  /// Handles GraphQL (nested, upper-case enums) and REST/SSE (flat ids).
  static Alert alertFromJson(Map<String, dynamic> json) {
    final city = json['city'] as Map<String, dynamic>?;
    final trip = json['trip'] as Map<String, dynamic>?;
    final driver = json['driver'] as Map<String, dynamic>?;
    return Alert(
      id: json['id'] as String,
      type: AlertType.parse(json['type']),
      severity: AlertSeverity.parse(json['severity']),
      message: '${json['message'] ?? ''}',
      createdAt: parseDate(json['createdAt']) ?? DateTime.now(),
      cityId: (city?['id'] ?? json['cityId']) as String?,
      cityName: city?['name'] as String?,
      tripId: (trip?['id'] ?? json['tripId']) as String?,
      driverId: (driver?['id'] ?? json['driverId']) as String?,
      driverName: driver?['name'] as String?,
      acknowledgedAt: parseDate(json['acknowledgedAt']),
      acknowledgedBy: json['acknowledgedBy'] as String?,
    );
  }
}
