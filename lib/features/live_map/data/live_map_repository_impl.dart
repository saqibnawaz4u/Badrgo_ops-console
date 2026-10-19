import '../../../core/domain/shared_entities.dart';
import '../../../core/network/graphql_client.dart';
import '../../../core/network/rest_client.dart';
import '../../../core/realtime/realtime_status.dart';
import '../../../core/realtime/server_events.dart';
import '../domain/entities/driver.dart';
import '../domain/repositories/live_map_repository.dart';

class LiveMapRepositoryImpl implements LiveMapRepository {
  LiveMapRepositoryImpl({required DriverSocket socket, required GraphQLClient graphQL})
      : _socket = socket,
        _graphQL = graphQL;

  final DriverSocket _socket;
  final GraphQLClient _graphQL;

  static const _driverQuery = r'''
    query Driver($id: ID!) {
      driver(id: $id) {
        id name phone status rating lastSeenAt
        vehicle { make model plate color }
        city { name }
        currentTrip { id status pickup { address } dropoff { address } rider { name } }
      }
    }
  ''';

  @override
  Stream<List<DriverLocation>> watchLocations() => _socket.channel('drivers.locations').map(
        (payload) => [
          for (final d in (payload['drivers'] as List? ?? const []))
            if (d is Map<String, dynamic> && d['lat'] is num && d['lng'] is num)
              DriverLocation(
                id: d['id'] as String,
                name: '${d['name'] ?? ''}',
                status: DriverStatus.parse(d['status']),
                position: GeoPoint((d['lat'] as num).toDouble(), (d['lng'] as num).toDouble()),
                cityId: d['cityId'] as String?,
                heading: (d['heading'] as num?)?.toDouble(),
                lastSeenAt: parseDate(d['lastSeenAt']),
              ),
        ],
      );

  @override
  Future<DriverDetails?> fetchDriver(String id) async {
    final data = await _graphQL.query(_driverQuery, variables: {'id': id});
    final d = data['driver'] as Map<String, dynamic>?;
    if (d == null) return null;
    final trip = d['currentTrip'] as Map<String, dynamic>?;
    return DriverDetails(
      id: d['id'] as String,
      name: '${d['name'] ?? ''}',
      status: DriverStatus.parse(d['status']),
      phone: d['phone'] as String?,
      rating: (d['rating'] as num?)?.toDouble(),
      vehicle: Vehicle.fromJson(d['vehicle']),
      cityName: (d['city'] as Map?)?['name'] as String?,
      lastSeenAt: parseDate(d['lastSeenAt']),
      currentTrip: trip == null
          ? null
          : CurrentTripSummary(
              id: trip['id'] as String,
              status: '${trip['status']}',
              pickup: '${(trip['pickup'] as Map?)?['address'] ?? ''}',
              dropoff: '${(trip['dropoff'] as Map?)?['address'] ?? ''}',
              riderName: (trip['rider'] as Map?)?['name'] as String?,
            ),
    );
  }

  @override
  RealtimeStatus get connectionStatus => _socket.status;

  @override
  Stream<RealtimeStatus> watchConnectionStatus() => _socket.statusStream;
}

class DriverChatRepositoryImpl implements DriverChatRepository {
  DriverChatRepositoryImpl({required DriverSocket socket, required RestClient rest})
      : _socket = socket,
        _rest = rest;

  final DriverSocket _socket;
  final RestClient _rest;

  @override
  Future<List<ChatMessage>> fetchHistory(String driverId) async {
    final body = await _rest.get('/api/drivers/$driverId/messages', query: {'limit': '100'});
    final list = body is Map ? body['data'] : body;
    return [
      for (final m in (list is List ? list : const []))
        if (m is Map<String, dynamic>) messageFromJson(m),
    ];
  }

  @override
  Stream<ChatMessage> watchMessages() => _socket
      .channel('driver.messages')
      .where((p) => p['message'] is Map<String, dynamic>)
      .map((p) => messageFromJson(p['message'] as Map<String, dynamic>));

  @override
  Future<ChatMessage> send({required String driverId, required String body}) async {
    final ack = await _socket.command('driver.message.send', {'driverId': driverId, 'body': body.trim()});
    return messageFromJson(ack['message'] as Map<String, dynamic>);
  }

  static ChatMessage messageFromJson(Map<String, dynamic> json) => ChatMessage(
        id: '${json['id']}',
        driverId: '${json['driverId']}',
        fromDriver: json['direction'] == 'from_driver',
        body: '${json['body'] ?? ''}',
        createdAt: parseDate(json['createdAt']) ?? DateTime.now(),
        sentBy: json['sentBy'] as String?,
      );
}
