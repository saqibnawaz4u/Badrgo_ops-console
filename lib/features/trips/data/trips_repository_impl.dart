import '../../../core/network/graphql_client.dart';
import '../../../core/network/rest_client.dart';
import '../../../core/realtime/server_events.dart';
import '../../../core/util/streams.dart';
import '../domain/entities/trip.dart';
import '../domain/entities/trip_filter.dart';
import '../domain/repositories/trips_repository.dart';
import 'trip_mapper.dart';

class TripsRepositoryImpl implements TripsRepository {
  TripsRepositoryImpl({
    required GraphQLClient graphQL,
    required RestClient rest,
    required ServerEvents events,
  })  : _graphQL = graphQL,
        _rest = rest,
        _events = events;

  final GraphQLClient _graphQL;
  final RestClient _rest;
  final ServerEvents _events;

  static const _tripsQuery = '''
    query Trips(\$filter: TripFilter, \$first: Int, \$after: String) {
      trips(filter: \$filter, first: \$first, after: \$after) {
        totalCount
        pageInfo { endCursor hasNextPage }
        nodes { ${TripMapper.listFields} }
      }
    }
  ''';

  static const _tripQuery = '''
    query Trip(\$id: ID!) { trip(id: \$id) { ${TripMapper.detailFields} } }
  ''';

  static const _availableDriversQuery = '''
    query AvailableDrivers(\$cityId: ID) {
      drivers(filter: { cityId: \$cityId, status: [AVAILABLE] }, first: 100) {
        nodes { id name rating vehicle { make model plate color } location { lat lng } }
      }
    }
  ''';

  @override
  Future<TripPage> fetchTrips({required TripFilter filter, String? after, int first = 25}) async {
    final data = await _graphQL.query(_tripsQuery, variables: {
      'filter': filter.toGraphQL(),
      'first': first,
      'after': ?after,
    });
    final trips = data['trips'] as Map<String, dynamic>;
    final pageInfo = trips['pageInfo'] as Map<String, dynamic>;
    return TripPage(
      trips: [for (final n in trips['nodes'] as List) TripMapper.fromJson(n as Map<String, dynamic>)],
      endCursor: pageInfo['endCursor'] as String?,
      hasNextPage: pageInfo['hasNextPage'] as bool? ?? false,
      totalCount: (trips['totalCount'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<Trip?> fetchTrip(String id) async {
    final data = await _graphQL.query(_tripQuery, variables: {'id': id});
    final trip = data['trip'];
    return trip == null ? null : TripMapper.fromJson(trip as Map<String, dynamic>);
  }

  @override
  Future<List<Trip>> fetchTripsByIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    // One request, one aliased field per id: t0: trip(id: $id0) { ... }
    final params = [for (var i = 0; i < ids.length; i++) '\$id$i: ID!'].join(', ');
    final fields = [
      for (var i = 0; i < ids.length; i++) 't$i: trip(id: \$id$i) { ${TripMapper.listFields} }',
    ].join('\n');
    final data = await _graphQL.query(
      'query TripsByIds($params) {\n$fields\n}',
      variables: {for (var i = 0; i < ids.length; i++) 'id$i': ids[i]},
    );
    return [
      for (final value in data.values)
        if (value is Map<String, dynamic>) TripMapper.fromJson(value),
    ];
  }

  @override
  Future<List<AssignableDriver>> fetchAvailableDrivers({String? cityId}) async {
    final data = await _graphQL.query(_availableDriversQuery, variables: {'cityId': ?cityId});
    final nodes = (data['drivers'] as Map<String, dynamic>)['nodes'] as List;
    return [for (final n in nodes) TripMapper.driverFromJson(n as Map<String, dynamic>)];
  }

  @override
  Stream<TripChange> watchChanges() => mergeStreams([
        _events.on('trip.created').map((e) => _change(e, isNew: true)),
        _events.on('trip.updated').map((e) => _change(e, isNew: false)),
      ]);

  static TripChange _change(ServerEvent event, {required bool isNew}) => TripChange(
        isNew: isNew,
        change: '${event.data['change'] ?? (isNew ? 'created' : 'updated')}',
        trip: TripMapper.fromJson(event.data['trip'] as Map<String, dynamic>),
      );

  @override
  Future<void> assignDriver({required String tripId, required String driverId}) =>
      _rest.post('/api/trips/$tripId/assign', body: {'driverId': driverId});

  @override
  Future<void> cancelTrip({required String tripId, required String reason}) =>
      _rest.post('/api/trips/$tripId/cancel', body: {'reason': reason.trim()});

  @override
  Future<void> refundTrip({required String tripId, required double amount, required String reason}) =>
      _rest.post('/api/trips/$tripId/refund', body: {'amount': amount, 'reason': reason.trim()});
}

